#!/usr/bin/env bash
set -euo pipefail

echo "=== STRAN/SROF · CLOUDFLARE SAFE INVENTORY ==="
echo "HOST=$(hostname -s)"
echo "TIME=$(date -Is)"

command -v cloudflared >/dev/null
command -v systemctl >/dev/null
command -v ss >/dev/null

redact() {
  sed -E \
    -e 's/(--token)([= ]+)[^ ]+/\1 REDACTED/g' \
    -e 's/(TUNNEL_TOKEN=).*/\1REDACTED/g' \
    -e 's/(token:).*/\1 REDACTED/g' \
    -e 's/(credentials-file:)[[:space:]]*.*/\1 PRESENT_REDACTED_PATH/g'
}

echo
echo "=== CLOUDFLARED BINARY ==="
command -v cloudflared
cloudflared --version || true

echo
echo "=== CLOUDFLARED SERVICE STATE ==="
systemctl is-active cloudflared.service || true
systemctl is-enabled cloudflared.service || true

echo
echo "=== CLOUDFLARED SERVICE METADATA · REDACTED ==="
{
  systemctl show cloudflared.service \
    -p FragmentPath \
    -p User \
    -p Group \
    -p EnvironmentFiles \
    -p ExecStart 2>/dev/null || true
} | redact

echo
echo "=== MANAGEMENT MODE HINT ==="
EXEC_RAW="$(systemctl show cloudflared.service -p ExecStart --value 2>/dev/null || true)"
if grep -Eq -- '(^|[[:space:]])--token-file([=[:space:]])' <<<"$EXEC_RAW"; then
  echo "CLOUDFLARED_MANAGEMENT_MODE=REMOTE_MANAGED_TOKEN_FILE"
elif grep -Eq -- '(^|[[:space:]])--token([=[:space:]])' <<<"$EXEC_RAW"; then
  echo "CLOUDFLARED_MANAGEMENT_MODE=REMOTE_MANAGED_TOKEN"
elif grep -Eq -- '(^|[[:space:]])(--config|-config)([=[:space:]])' <<<"$EXEC_RAW"; then
  echo "CLOUDFLARED_MANAGEMENT_MODE=CONFIG_FILE"
else
  echo "CLOUDFLARED_MANAGEMENT_MODE=UNRESOLVED"
fi

echo
echo "=== COMMON CONFIG FILES ==="
FOUND_CONFIG=0
for f in \
  /etc/cloudflared/config.yml \
  /etc/cloudflared/config.yaml \
  /usr/local/etc/cloudflared/config.yml \
  /usr/local/etc/cloudflared/config.yaml
do
  if [ -r "$f" ]; then
    FOUND_CONFIG=1
    echo "CONFIG_FILE=$f"
    echo "--- SAFE KEYS ---"
    grep -E '^[[:space:]]*(tunnel|credentials-file|hostname|service|required|teamName|audTag|connectTimeout):' "$f" \
      | redact || true
    echo "--- END SAFE KEYS ---"
  fi
done
if [ "$FOUND_CONFIG" -eq 0 ]; then
  echo "CONFIG_FILE=NONE_IN_COMMON_PATHS"
fi

echo
echo "=== /etc/cloudflared FILE NAMES ONLY ==="
if [ -d /etc/cloudflared ]; then
  find /etc/cloudflared -maxdepth 1 -type f -printf '%f\n' | sort
else
  echo "ETC_CLOUDFLARED=ABSENT"
fi

echo
echo "=== TUNNEL LIST · NON-SECRET METADATA ==="
TMP="$(mktemp)"
trap 'rm -f "$TMP"' EXIT
if cloudflared tunnel list --output json >"$TMP" 2>/dev/null; then
  python3 - "$TMP" <<'PY'
import json,sys
try:
    rows=json.load(open(sys.argv[1],encoding="utf-8"))
except Exception as exc:
    print("TUNNEL_LIST_PARSE=FAIL",type(exc).__name__)
    raise SystemExit(0)
print("TUNNEL_LIST=PASS")
for row in rows:
    print("TUNNEL id=%s name=%s created=%s deleted=%s connections=%s" % (
        row.get("id",""),
        row.get("name",""),
        row.get("created_at") or row.get("createdAt") or "",
        row.get("deleted_at") or row.get("deletedAt") or "",
        len(row.get("connections") or []),
    ))
PY
else
  echo "TUNNEL_LIST=UNAVAILABLE_WITH_CURRENT_LOCAL_AUTH"
fi

echo
echo "=== SROF LOCAL ORIGIN ==="
systemctl is-active scientiam-remote-ops-gateway.service || true
systemctl is-enabled scientiam-remote-ops-gateway.service || true
if ss -ltn | grep -Fq '127.0.0.1:8765'; then
  echo "SROF_LOOPBACK_BIND=PASS"
else
  echo "SROF_LOOPBACK_BIND=FAIL"
fi
if ss -ltn | grep -Eq '0\.0\.0\.0:8765|\[::\]:8765'; then
  echo "SROF_EXTERNAL_BIND=FAIL"
else
  echo "SROF_EXTERNAL_BIND=NONE"
fi

echo
echo "=== SROF CLOUDFLARE ACCESS ENV ==="
ACCESS_ENV="/etc/scientiam/remote-ops/cloudflare-access.env"
if [ -r "$ACCESS_ENV" ]; then
  echo "SROF_CF_ACCESS_ENV=PRESENT"
  grep -E '^(SROF_CF_ACCESS_REQUIRED|SROF_CF_TEAM_DOMAIN|SROF_CF_ACCESS_AUD)=' "$ACCESS_ENV" || true
else
  echo "SROF_CF_ACCESS_ENV=ABSENT"
fi

echo
echo "CLOUDFLARE_SAFE_INVENTORY=COMPLETE"
echo "NO_SECRET_CONTENT_PRINTED=YES"
echo "NO_CONFIGURATION_CHANGED=YES"
echo "DCP_USED=NO"
echo "GITHUB_ACTIONS_TRANSPORT=NO"
