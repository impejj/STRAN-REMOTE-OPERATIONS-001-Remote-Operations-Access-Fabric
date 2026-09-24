#!/usr/bin/env bash
set -euo pipefail

SERVICE="cloudflared-scientiam-srof.service"
TOKEN_FILE="/etc/cloudflared/scientiam-srof.token"

if [ "$(id -u)" -ne 0 ]; then
  echo "BLOCKED: run with sudo/root" >&2
  exit 3
fi

echo "=== STRAN/SROF · INSTALL DEDICATED CLOUDFLARE TOKEN ==="
echo "HOST=$(hostname -s)"
echo "TIME=$(date -Is)"

test "$(hostname -s)" = "profesys-scientiam"
test -f "/etc/systemd/system/$SERVICE"
install -d -m 0755 /etc/cloudflared

read -r -s -p "Paste ONLY the new scientiam-srof tunnel token, then press Enter: " TOKEN
echo
if [ -z "$TOKEN" ]; then
  echo "BLOCKED: empty token" >&2
  exit 10
fi

umask 077
printf "%s\n" "$TOKEN" > "$TOKEN_FILE"
unset TOKEN
chown root:root "$TOKEN_FILE"
chmod 0600 "$TOKEN_FILE"

echo "TOKEN_FILE_PRESENT=YES"
stat -c "TOKEN_FILE_MODE=%a TOKEN_FILE_OWNER=%U TOKEN_FILE_GROUP=%G TOKEN_FILE_BYTES=%s" "$TOKEN_FILE"
echo "TOKEN_CONTENT_PRINTED=NO"

systemctl daemon-reload
systemctl enable --now "$SERVICE"
sleep 2
systemctl is-active --quiet "$SERVICE"
echo "DEDICATED_TUNNEL_SERVICE=PASS"
echo "TOKEN_CONTENT_PRINTED=NO"
echo "DCP_USED=NO"
echo "GITHUB_ACTIONS_TRANSPORT=NO"
