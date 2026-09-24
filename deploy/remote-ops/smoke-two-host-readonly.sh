#!/usr/bin/env bash
set -euo pipefail

SERVICE_USER="${SROF_SERVICE_USER:-scientiam-remoteops}"
SERVICE_GROUP="${SROF_SERVICE_GROUP:-scientiam-remoteops}"
HOSTS="${SROF_HOSTS_FILE:-/etc/scientiam/remote-ops/hosts.json}"
RECEIPTS="${SROF_RECEIPT_DIR:-/var/lib/scientiam/remote-ops/receipts}"
APP_DIR="${SROF_APP_DIR:-/opt/scientiam/remote-ops-gateway}"

if [ "$(id -u)" -ne 0 ]; then
  echo "BLOCKED: run with sudo/root" >&2
  exit 3
fi

echo "=== STRAN/SROF · TWO-HOST READ-ONLY FUNCTIONAL SMOKE ==="
echo "HOST=$(hostname -s)"
echo "TIME=$(date -Is)"

test "$(hostname -s)" = "profesys-scientiam"
id "$SERVICE_USER" >/dev/null
getent group "$SERVICE_GROUP" >/dev/null
test -r "$HOSTS"
test -x "$APP_DIR/.venv/bin/python"
install -d -m 0750 -o "$SERVICE_USER" -g "$SERVICE_GROUP" "$RECEIPTS"

BEFORE="$(find "$RECEIPTS" -maxdepth 1 -type f -name 'SROF-*.json' 2>/dev/null | wc -l)"
echo "RECEIPTS_BEFORE=$BEFORE"

runuser -u "$SERVICE_USER" -- env \
  SROF_HOSTS_FILE="$HOSTS" \
  SROF_RECEIPT_DIR="$RECEIPTS" \
  "$APP_DIR/.venv/bin/python" - <<'PY'
from srof_gateway.server import (
    hosts_list,
    host_health,
    process_list,
    network_listeners,
    fs_list,
    git_status,
)

def ok(name, cond, detail=""):
    print(f"{name}={'PASS' if cond else 'FAIL'}{(' ' + detail) if detail else ''}")
    if not cond:
        raise SystemExit(41)

hosts = hosts_list()
ids = {h["host_id"] for h in hosts}
ok("HOSTS_LIST_TWO_HOSTS", {"PROFESYS-SCIENTIAM", "THINKPAD-E470"} <= ids)

for host in ("PROFESYS-SCIENTIAM", "THINKPAD-E470"):
    r = host_health(host)
    ok(f"HOST_HEALTH_{host}", bool(r.get("ok")), f"REQUEST_ID={r['receipt']['request_id']}")

    r = process_list(host, limit=8)
    ok(f"PROCESS_LIST_{host}", bool(r.get("ok")), f"REQUEST_ID={r['receipt']['request_id']}")

    r = network_listeners(host)
    ok(f"NETWORK_LISTENERS_{host}", bool(r.get("ok")), f"REQUEST_ID={r['receipt']['request_id']}")

r = fs_list("THINKPAD-E470", "/home/impejj/work/profesys", limit=20)
ok("FS_LIST_THINKPAD", bool(r.get("ok")), f"REQUEST_ID={r['receipt']['request_id']}")

r = git_status("THINKPAD-E470", "/home/impejj/work/profesys/scientiam")
ok("GIT_STATUS_THINKPAD", bool(r.get("ok")), f"REQUEST_ID={r['receipt']['request_id']}")

try:
    fs_list("PROFESYS-SCIENTIAM", "/etc", limit=5)
except PermissionError as exc:
    print("DENY_SERVER_FILESYSTEM=PASS", str(exc))
else:
    print("DENY_SERVER_FILESYSTEM=FAIL")
    raise SystemExit(42)

try:
    git_status("PROFESYS-SCIENTIAM", "/tmp")
except PermissionError as exc:
    print("DENY_SERVER_GIT=PASS", str(exc))
else:
    print("DENY_SERVER_GIT=FAIL")
    raise SystemExit(43)

print("SROF_READONLY_FUNCTIONAL_SMOKE=PASS")
PY

AFTER="$(find "$RECEIPTS" -maxdepth 1 -type f -name 'SROF-*.json' 2>/dev/null | wc -l)"
echo "RECEIPTS_AFTER=$AFTER"

if [ "$AFTER" -lt $((BEFORE + 8)) ]; then
  echo "RECEIPT_DELTA=FAIL expected_at_least=8 actual=$((AFTER-BEFORE))" >&2
  exit 44
fi

echo "RECEIPT_DELTA=PASS actual=$((AFTER-BEFORE))"
echo "DCP_USED=NO"
echo "GITHUB_ACTIONS_TRANSPORT=NO"
echo "SROF_TWO_HOST_READONLY=PASS"
