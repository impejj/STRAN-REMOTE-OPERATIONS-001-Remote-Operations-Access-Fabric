#!/usr/bin/env bash
set -euo pipefail

REMOTE_USER="scientiam-remoteops"
SERVER_PUBKEY='ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIBekfb+V1no/uqbCpFDmKH6udDeI42JzzjdW2cmM8Alv STRAN-REMOTE-OPERATIONS-001 server-to-thinkpad'

if [ "$(id -u)" -ne 0 ]; then
  echo "ERROR: run with sudo/root" >&2
  exit 3
fi

echo "=== STRAN-REMOTE-OPERATIONS-001 · THINKPAD BOOTSTRAP ==="
echo "HOST=$(hostname -s)"
echo "TIME_UTC=$(date -u +%Y-%m-%dT%H:%M:%SZ)"

if ! command -v sshd >/dev/null 2>&1; then
  echo "Installing openssh-server..."
  apt-get update
  DEBIAN_FRONTEND=noninteractive apt-get install -y openssh-server
fi

if ! id "$REMOTE_USER" >/dev/null 2>&1; then
  useradd --create-home --shell /bin/bash "$REMOTE_USER"
fi

install -d -m 0700 -o "$REMOTE_USER" -g "$REMOTE_USER" "/home/$REMOTE_USER/.ssh"
AUTH="/home/$REMOTE_USER/.ssh/authorized_keys"
touch "$AUTH"
chown "$REMOTE_USER:$REMOTE_USER" "$AUTH"
chmod 0600 "$AUTH"

if ! grep -Fqx "$SERVER_PUBKEY" "$AUTH"; then
  printf '%s\n' "$SERVER_PUBKEY" >> "$AUTH"
fi

install -d -m 0750 -o "$REMOTE_USER" -g "$REMOTE_USER" /var/lib/scientiam/remote-ops
install -d -m 0750 -o "$REMOTE_USER" -g "$REMOTE_USER" /var/log/scientiam/remote-ops

sshd -t
systemctl enable --now ssh

echo "SSH_ACTIVE=$(systemctl is-active ssh)"
echo "SSH_ENABLED=$(systemctl is-enabled ssh)"
echo "REMOTE_USER=$REMOTE_USER"
echo "AUTHORIZED_KEY_FINGERPRINT=SHA256:Ri+NScFs8xmNjtXalxs6VmB+KULf0Y4Qs1awmGO1Zug"
echo "IPV4:"
ip -4 -br addr | awk '$1 != "lo" {print}'
echo "LISTEN_22:"
ss -ltn '( sport = :22 )' || true
echo "CURRENT_ACCESS_NOT_REMOVED=YES"
echo "DCP_UNTOUCHED=YES"
echo "FIREWALL_UNTOUCHED=YES"
echo "ROOT_SSH_POLICY_UNTOUCHED=YES"
echo "PASSWORD_POLICY_UNTOUCHED=YES"
echo "BOOTSTRAP_RESULT=PASS"
