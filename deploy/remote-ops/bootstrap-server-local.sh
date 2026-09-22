#!/usr/bin/env bash
set -euo pipefail

REMOTE_USER="scientiam-remoteops"
AUTHORIZED_KEY_FILE=""

usage() {
  cat <<EOF
Usage: $0 [--authorized-key-file PATH] [--user NAME]

Bootstraps the local SERVER side of STRAN-REMOTE-OPERATIONS-001.
It installs/enables OpenSSH if needed, creates the dedicated remote-ops
account and optionally installs one approved public key from a local file.

No firewall, root-login, password-authentication, sudoers or DCP policy is
changed by this script.
EOF
}

while [ $# -gt 0 ]; do
  case "$1" in
    --authorized-key-file) AUTHORIZED_KEY_FILE="$2"; shift 2 ;;
    --user) REMOTE_USER="$2"; shift 2 ;;
    -h|--help) usage; exit 0 ;;
    *) echo "Unknown argument: $1" >&2; usage; exit 2 ;;
  esac
done

if [ "$(id -u)" -ne 0 ]; then
  echo "ERROR: run with sudo/root" >&2
  exit 3
fi

echo "=== STRAN-REMOTE-OPERATIONS-001 · SERVER BOOTSTRAP ==="
echo "HOST=$(hostname -s)"
echo "TIME_UTC=$(date -u +%Y-%m-%dT%H:%M:%SZ)"

if ! command -v sshd >/dev/null 2>&1; then
  echo "Installing openssh-server..."
  apt-get update
  DEBIAN_FRONTEND=noninteractive apt-get install -y openssh-server
fi

install -d -m 0755 -o root -g root /run/sshd

if ! id "$REMOTE_USER" >/dev/null 2>&1; then
  useradd --create-home --shell /bin/bash "$REMOTE_USER"
fi

install -d -m 0700 -o "$REMOTE_USER" -g "$REMOTE_USER" "/home/$REMOTE_USER/.ssh"
AUTH="/home/$REMOTE_USER/.ssh/authorized_keys"
touch "$AUTH"
chown "$REMOTE_USER:$REMOTE_USER" "$AUTH"
chmod 0600 "$AUTH"

if [ -n "$AUTHORIZED_KEY_FILE" ]; then
  if [ ! -f "$AUTHORIZED_KEY_FILE" ]; then
    echo "ERROR: authorized key file not found: $AUTHORIZED_KEY_FILE" >&2
    exit 4
  fi
  PUBKEY="$(tr -d '\r\n' < "$AUTHORIZED_KEY_FILE")"
  case "$PUBKEY" in
    ssh-ed25519\ *|ssh-rsa\ *|ecdsa-sha2-nistp256\ *|ecdsa-sha2-nistp384\ *|ecdsa-sha2-nistp521\ *) ;;
    *) echo "ERROR: file does not contain a supported SSH public key" >&2; exit 5 ;;
  esac
  if ! grep -Fqx "$PUBKEY" "$AUTH"; then
    printf '%s\n' "$PUBKEY" >> "$AUTH"
  fi
  echo "AUTHORIZED_KEY_INSTALLED=YES"
else
  echo "AUTHORIZED_KEY_INSTALLED=NO"
  echo "NEXT_KEY_STEP=rerun with --authorized-key-file after generating the dedicated ThinkPad-to-SERVER key"
fi

install -d -m 0750 -o "$REMOTE_USER" -g "$REMOTE_USER" /var/lib/scientiam/remote-ops
install -d -m 0750 -o "$REMOTE_USER" -g "$REMOTE_USER" /var/log/scientiam/remote-ops

sshd -t
systemctl enable --now ssh

echo "SSH_ACTIVE=$(systemctl is-active ssh)"
echo "SSH_ENABLED=$(systemctl is-enabled ssh)"
echo "REMOTE_USER=$REMOTE_USER"
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
