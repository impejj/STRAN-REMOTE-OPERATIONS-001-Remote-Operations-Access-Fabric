#!/usr/bin/env bash
set -euo pipefail

REMOTE_USER="scientiam-remoteops"
REMOTE_GROUP="scientiam-remoteops"
SSH_DIR="/home/$REMOTE_USER/.ssh"
KEY="$SSH_DIR/srof_gateway_to_server"
AUTH="$SSH_DIR/authorized_keys"
CONFIG="$SSH_DIR/config"
KNOWN="$SSH_DIR/known_hosts"
ETC_DIR="/etc/scientiam/remote-ops"
HOSTS="$ETC_DIR/hosts.json"
STATE_DIR="/var/lib/scientiam/remote-ops"
RECEIPTS="$STATE_DIR/receipts"
SERVICE="scientiam-remote-ops-gateway.service"

REPO_ROOT="$(cd "$(dirname "$BASH_SOURCE")/../.." && pwd)"
PREPARE="$REPO_ROOT/deploy/remote-ops/prepare-gateway-server.sh"

if [ "$(id -u)" -ne 0 ]; then
  echo "ERROR: run with sudo/root" >&2
  exit 3
fi

echo "=== STRAN/SROF · SERVER GATEWAY ACTIVATION ==="
echo "HOST=$(hostname -s)"
echo "TIME=$(date -Is)"

test "$(hostname -s)" = "profesys-scientiam"
id "$REMOTE_USER" >/dev/null
getent group "$REMOTE_GROUP" >/dev/null
test -x "$PREPARE"
command -v ssh >/dev/null
command -v ssh-keygen >/dev/null
command -v systemctl >/dev/null

install -d -m 0700 -o "$REMOTE_USER" -g "$REMOTE_GROUP" "$SSH_DIR"
install -d -m 0750 -o root -g "$REMOTE_GROUP" "$ETC_DIR"
install -d -m 0750 -o "$REMOTE_USER" -g "$REMOTE_GROUP" "$STATE_DIR" "$RECEIPTS"

if [ ! -f "$KEY" ]; then
  runuser -u "$REMOTE_USER" -- ssh-keygen -t ed25519 -a 100 -N "" -f "$KEY" -C "STRAN-REMOTE-OPERATIONS-001 gateway-to-server"
  echo "GATEWAY_KEY_CREATED=YES"
else
  echo "GATEWAY_KEY_CREATED=NO_REUSED"
fi

touch "$AUTH"
chown "$REMOTE_USER:$REMOTE_GROUP" "$AUTH"
chmod 0600 "$AUTH"

PUB="$(cat "$KEY.pub")"
if ! grep -Fqx "$PUB" "$AUTH"; then
  printf '%s\n' "$PUB" >> "$AUTH"
  echo "SELF_AUTHORIZED_KEY_ADDED=YES"
else
  echo "SELF_AUTHORIZED_KEY_ADDED=NO_ALREADY_PRESENT"
fi

HOSTKEY="$(awk '{print $1" "$2}' /etc/ssh/ssh_host_ed25519_key.pub)"
cat > "$KNOWN" <<EOF
127.0.0.1 $HOSTKEY
localhost $HOSTKEY
EOF
chown "$REMOTE_USER:$REMOTE_GROUP" "$KNOWN"
chmod 0600 "$KNOWN"

cat > "$CONFIG" <<EOF
Host profesys-scientiam-local-srof
    HostName 127.0.0.1
    User $REMOTE_USER
    IdentityFile $KEY
    IdentitiesOnly yes
    BatchMode yes
    PasswordAuthentication no
    StrictHostKeyChecking yes
    ServerAliveInterval 30
    ServerAliveCountMax 3
EOF
chown "$REMOTE_USER:$REMOTE_GROUP" "$CONFIG"
chmod 0600 "$CONFIG"

echo
echo "=== SELF-SSH PREFLIGHT ==="
runuser -u "$REMOTE_USER" -- ssh profesys-scientiam-local-srof 'echo "SELF_SSH=PASS"; echo "HOST=$(hostname -s)"; echo "USER=$(id -un)"'

cat > "$HOSTS" <<'EOF'
{
  "schema": "SCIENTIAM_REMOTE_OPS_HOST_REGISTRY/0.1",
  "hosts": [
    {
      "schema": "SCIENTIAM_REMOTE_OPS_HOST/0.1",
      "host_id": "PROFESYS-SCIENTIAM",
      "owner_id": "PROFESYS",
      "ssh_alias": "profesys-scientiam-local-srof",
      "capabilities": ["PROCESS", "NETWORK"],
      "allowed_roots": [],
      "allowed_services": [],
      "allowed_containers": [],
      "allowed_repositories": [],
      "allowed_data_classes": ["PUBLIC", "SYNTHETIC", "INTERNAL_LOW", "CONFIDENTIAL"],
      "lifecycle_state": "AUTHORIZED",
      "notes": "Initial P0 registry. Expand allowlists only after verified live inventory."
    }
  ]
}
EOF
chown root:"$REMOTE_GROUP" "$HOSTS"
chmod 0640 "$HOSTS"
python3 -m json.tool "$HOSTS" >/dev/null

echo
echo "=== INSTALL + ACTIVATE GATEWAY ==="
"$PREPARE" activate

echo
echo "=== SERVICE VERIFY ==="
systemctl is-active "$SERVICE"
systemctl is-enabled "$SERVICE"

if ss -ltn | grep -Fq "127.0.0.1:8765"; then
  echo "LOOPBACK_BIND=PASS"
else
  echo "LOOPBACK_BIND=FAIL" >&2
  systemctl status "$SERVICE" --no-pager -l || true
  exit 10
fi

if ss -ltn | grep -Eq "0\.0\.0\.0:8765|\[::\]:8765"; then
  echo "EXTERNAL_BIND=FAIL" >&2
  exit 11
else
  echo "EXTERNAL_BIND=NONE"
fi

echo
echo "=== DIRECT TOOL + RECEIPT PROOF ==="
BEFORE="$(find "$RECEIPTS" -maxdepth 1 -type f -name 'SROF-*.json' | wc -l)"
runuser -u "$REMOTE_USER" -- env SROF_HOSTS_FILE="$HOSTS" SROF_RECEIPT_DIR="$RECEIPTS" /opt/scientiam/remote-ops-gateway/.venv/bin/python - <<'PY'
from srof_gateway.server import host_health
result = host_health("PROFESYS-SCIENTIAM")
print("HOST_HEALTH_OK=", result["ok"])
print("REQUEST_ID=", result["receipt"]["request_id"])
print("EXIT_CODE=", result["receipt"]["exit_code"])
PY
AFTER="$(find "$RECEIPTS" -maxdepth 1 -type f -name 'SROF-*.json' | wc -l)"

if [ "$AFTER" -le "$BEFORE" ]; then
  echo "RECEIPT_PROOF=FAIL" >&2
  exit 12
fi
echo "RECEIPT_PROOF=PASS"

echo
echo "=== RECEIPT TAIL ==="
find "$RECEIPTS" -maxdepth 1 -type f -name 'SROF-*.json' -printf '%T@ %p\n' | sort -n | tail -1 | cut -d' ' -f2- | xargs -r cat

echo
echo "SROF_SERVER_GATEWAY_ACTIVATION=PASS"
echo "DCP_UNTOUCHED=YES"
echo "FIREWALL_UNTOUCHED=YES"
echo "SUDOERS_UNTOUCHED=YES"
