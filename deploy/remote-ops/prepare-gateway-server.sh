#!/usr/bin/env bash
set -euo pipefail

MODE="${1:-prepare}"
case "$MODE" in
  prepare|activate|status) ;;
  *) echo "usage: $0 [prepare|activate|status]" >&2; exit 2 ;;
esac

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
APP_DIR="${SROF_APP_DIR:-/opt/scientiam/remote-ops-gateway}"
ETC_DIR="${SROF_ETC_DIR:-/etc/scientiam/remote-ops}"
STATE_DIR="${SROF_STATE_DIR:-/var/lib/scientiam/remote-ops}"
RECEIPT_DIR="${SROF_RECEIPT_DIR:-$STATE_DIR/receipts}"
SERVICE_USER="${SROF_SERVICE_USER:-scientiam-remoteops}"
SERVICE_GROUP="${SROF_SERVICE_GROUP:-scientiam-remoteops}"
SERVICE_NAME="scientiam-remote-ops-gateway.service"
UNIT_SOURCE="$REPO_ROOT/gateway/systemd/$SERVICE_NAME"
UNIT_TARGET="/etc/systemd/system/$SERVICE_NAME"

require_root() {
  if [[ "${EUID}" -ne 0 ]]; then
    echo "BLOCKED: run with sudo/root" >&2
    exit 3
  fi
}

status() {
  echo "REPO_ROOT=$REPO_ROOT"
  echo "APP_DIR=$APP_DIR"
  echo "HOSTS_FILE=$ETC_DIR/hosts.json"
  echo "RECEIPT_DIR=$RECEIPT_DIR"
  id "$SERVICE_USER" 2>/dev/null || true
  systemctl is-enabled "$SERVICE_NAME" 2>/dev/null || true
  systemctl is-active "$SERVICE_NAME" 2>/dev/null || true
  systemctl status "$SERVICE_NAME" --no-pager -l 2>/dev/null | tail -40 || true
}

if [[ "$MODE" == "status" ]]; then
  status
  exit 0
fi

require_root
command -v python3 >/dev/null
test -f "$REPO_ROOT/gateway/pyproject.toml"
test -f "$UNIT_SOURCE"
id "$SERVICE_USER" >/dev/null
getent group "$SERVICE_GROUP" >/dev/null

install -d -m 0755 "$APP_DIR"
install -d -m 0750 -o root -g "$SERVICE_GROUP" "$ETC_DIR"
install -d -m 0750 -o "$SERVICE_USER" -g "$SERVICE_GROUP" "$STATE_DIR" "$RECEIPT_DIR"

# Copy forward without deleting unknown files. This keeps preparation reversible.
cp -a "$REPO_ROOT/gateway/." "$APP_DIR/"

if [[ ! -x "$APP_DIR/.venv/bin/python" ]]; then
  python3 -m venv "$APP_DIR/.venv"
fi
"$APP_DIR/.venv/bin/python" -m pip install --upgrade pip
"$APP_DIR/.venv/bin/pip" install --no-cache-dir -e "$APP_DIR"

chown -R "$SERVICE_USER:$SERVICE_GROUP" "$APP_DIR"
install -m 0644 "$UNIT_SOURCE" "$UNIT_TARGET"
systemctl daemon-reload

echo "PREPARE=PASS"
echo "HOSTS_FILE_PRESENT=$([[ -s "$ETC_DIR/hosts.json" ]] && echo YES || echo NO)"
echo "SERVICE_ENABLED=$(systemctl is-enabled "$SERVICE_NAME" 2>/dev/null || true)"
echo "SERVICE_ACTIVE=$(systemctl is-active "$SERVICE_NAME" 2>/dev/null || true)"

if [[ "$MODE" == "activate" ]]; then
  if [[ ! -s "$ETC_DIR/hosts.json" ]]; then
    echo "BLOCKED: $ETC_DIR/hosts.json is required before activation" >&2
    exit 4
  fi
  systemctl enable --now "$SERVICE_NAME"
  sleep 1
  systemctl is-active --quiet "$SERVICE_NAME"
  echo "ACTIVATE=PASS"
fi
