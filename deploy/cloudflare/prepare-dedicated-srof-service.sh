#!/usr/bin/env bash
set -euo pipefail

MODE="plan"
SERVICE_NAME="cloudflared-scientiam-srof.service"
CLOUDFLARED_BIN="${CLOUDFLARED_BIN:-/usr/local/bin/cloudflared}"
TOKEN_FILE="${SROF_CF_TUNNEL_TOKEN_FILE:-/etc/cloudflared/scientiam-srof.token}"
UNIT_FILE="/etc/systemd/system/$SERVICE_NAME"

usage() {
  cat <<'EOF'
Usage:
  sudo deploy/cloudflare/prepare-dedicated-srof-service.sh
  sudo deploy/cloudflare/prepare-dedicated-srof-service.sh --apply

PLAN mode is read-only.

--apply installs a dedicated systemd unit for the future remotely-managed
Cloudflare tunnel scientiam-srof, but DOES NOT start it unless the dedicated
token file already exists and is mode 600 root:root.

This never reads token contents and never modifies the existing
cloudflared.service used by gastos-mama.
EOF
}

while [ "$#" -gt 0 ]; do
  case "$1" in
    --apply) MODE="apply"; shift ;;
    -h|--help) usage; exit 0 ;;
    *) echo "ERROR unknown argument: $1" >&2; usage; exit 2 ;;
  esac
done

echo "=== STRAN/SROF · DEDICATED CLOUDFLARE SERVICE PREP ==="
echo "MODE=$MODE"
echo "HOST=$(hostname -s)"
echo "TIME=$(date -Is)"

test "$(hostname -s)" = "profesys-scientiam"
test -x "$CLOUDFLARED_BIN"

echo
echo "=== EXISTING TUNNEL SAFETY ==="
systemctl is-active cloudflared.service || true
systemctl is-enabled cloudflared.service || true
EXISTING_EXEC="$(systemctl show cloudflared.service -p ExecStart --value 2>/dev/null || true)"
if grep -Fq '/etc/cloudflared/token' <<<"$EXISTING_EXEC"; then
  echo "EXISTING_GASTOS_TUNNEL_TOKEN_FILE=PASS"
else
  echo "EXISTING_GASTOS_TUNNEL_TOKEN_FILE=UNEXPECTED"
fi
echo "EXISTING_CLOUDFLARED_SERVICE_UNCHANGED=YES"

echo
echo "=== DEDICATED SROF UNIT PLAN ==="
echo "SERVICE_NAME=$SERVICE_NAME"
echo "TOKEN_FILE=$TOKEN_FILE"
echo "ORIGIN=http://127.0.0.1:8765"
echo "PUBLIC_HOSTNAME=TO_BE_CREATED_IN_CLOUDFLARE"
echo "CLOUDFLARE_ACCESS=NOT_USED"
echo "AUTH_MODEL=SROF_NATIVE_OAUTH_KEYCLOAK"

if [ "$MODE" != "apply" ]; then
  echo
  echo "PLAN_ONLY=PASS"
  exit 0
fi

if [ "$(id -u)" -ne 0 ]; then
  echo "BLOCKED: --apply requires sudo/root" >&2
  exit 3
fi

install -d -m 0755 /etc/cloudflared

cat > "$UNIT_FILE" <<EOF
[Unit]
Description=Cloudflare Tunnel - SCIENTIAM SROF
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
ExecStart=$CLOUDFLARED_BIN --no-autoupdate tunnel run --token-file $TOKEN_FILE
Restart=on-failure
RestartSec=5
NoNewPrivileges=true
PrivateTmp=true
ProtectSystem=strict
ProtectHome=true
ReadOnlyPaths=$TOKEN_FILE
CapabilityBoundingSet=
LockPersonality=true
RestrictSUIDSGID=true

[Install]
WantedBy=multi-user.target
EOF

chmod 0644 "$UNIT_FILE"
systemctl daemon-reload
echo "DEDICATED_UNIT_INSTALLED=PASS"

if [ -f "$TOKEN_FILE" ]; then
  META="$(stat -c '%a %U %G' "$TOKEN_FILE")"
  echo "TOKEN_FILE_META=$META"
  if [ "$META" != "600 root root" ]; then
    echo "BLOCKED: token file must be mode 600 root:root" >&2
    exit 10
  fi
  echo "TOKEN_FILE_PRESENT=YES"
  echo "TOKEN_CONTENT_READ=NO"
  systemctl enable --now "$SERVICE_NAME"
  systemctl is-active --quiet "$SERVICE_NAME"
  echo "DEDICATED_TUNNEL_SERVICE=PASS"
else
  echo "TOKEN_FILE_PRESENT=NO"
  echo "DEDICATED_TUNNEL_SERVICE=PREPARED_NOT_STARTED"
fi

echo "EXISTING_CLOUDFLARED_SERVICE_UNCHANGED=YES"
echo "DCP_USED=NO"
echo "GITHUB_ACTIONS_TRANSPORT=NO"
