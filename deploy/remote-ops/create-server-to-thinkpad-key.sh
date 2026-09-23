#!/usr/bin/env bash
set -euo pipefail

KEY_PATH="${1:-$HOME/.ssh/stran_remoteops_server_to_thinkpad}"
COMMENT="${2:-STRAN-REMOTE-OPERATIONS-001 server-to-thinkpad}"

mkdir -p "$HOME/.ssh"
chmod 700 "$HOME/.ssh"

if [ -e "$KEY_PATH" ] || [ -e "$KEY_PATH.pub" ]; then
  echo "KEY_EXISTS=YES"
else
  ssh-keygen -t ed25519 -a 100 -N "" -f "$KEY_PATH" -C "$COMMENT"
  chmod 600 "$KEY_PATH"
  chmod 644 "$KEY_PATH.pub"
  echo "KEY_CREATED=YES"
fi

echo "PRIVATE_KEY_PATH=$KEY_PATH"
echo "PUBLIC_KEY_PATH=$KEY_PATH.pub"
echo "PUBLIC_KEY_FINGERPRINT=$(ssh-keygen -lf "$KEY_PATH.pub" | awk '{print $2}')"
echo "PUBLIC_KEY_BEGIN"
cat "$KEY_PATH.pub"
echo "PUBLIC_KEY_END"
