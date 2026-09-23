#!/usr/bin/env bash
set -euo pipefail

EXPECTED_FINGERPRINT="${1:-SHA256:Ri+NScFs8xmNjtXalxs6VmB+KULf0Y4Qs1awmGO1Zug}"
SSH_DIR="${HOME}/.ssh"

echo "=== STRAN-REMOTE-OPERATIONS-001 · SERVER→THINKPAD KEY DISCOVERY ==="
echo "USER=$(id -un)"
echo "HOST=$(hostname -s)"
echo "EXPECTED_FINGERPRINT=$EXPECTED_FINGERPRINT"

if [ ! -d "$SSH_DIR" ]; then
  echo "SSH_DIR_PRESENT=NO"
  echo "MATCH_FOUND=NO"
  exit 0
fi

found=0
while IFS= read -r -d '' pub; do
  fp="$(ssh-keygen -lf "$pub" 2>/dev/null | awk '{print $2}' || true)"
  [ -n "$fp" ] || continue
  echo "PUBLIC_KEY=$(basename "$pub") FINGERPRINT=$fp"
  if [ "$fp" = "$EXPECTED_FINGERPRINT" ]; then
    echo "MATCH_PUBLIC_KEY=$pub"
    priv="${pub%.pub}"
    if [ -f "$priv" ]; then
      echo "MATCH_PRIVATE_KEY_PRESENT=YES"
      echo "MATCH_PRIVATE_KEY_PATH=$priv"
    else
      echo "MATCH_PRIVATE_KEY_PRESENT=NO"
    fi
    found=1
  fi
done < <(find "$SSH_DIR" -maxdepth 1 -type f -name '*.pub' -print0)

if [ "$found" -eq 1 ]; then
  echo "MATCH_FOUND=YES"
else
  echo "MATCH_FOUND=NO"
fi
