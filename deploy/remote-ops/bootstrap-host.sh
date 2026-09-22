#!/usr/bin/env bash
set -euo pipefail

MODE="plan"
REMOTE_USER="scientiam-remoteops"

usage() {
  cat <<EOF
Usage: $0 [--apply] [--user NAME]

Default mode is PLAN ONLY. --apply creates the service account and state
directories but does not change sshd authentication policy, firewall rules,
sudoers, or DCP.
EOF
}

while [ $# -gt 0 ]; do
  case "$1" in
    --apply) MODE="apply"; shift ;;
    --user) REMOTE_USER="$2"; shift 2 ;;
    -h|--help) usage; exit 0 ;;
    *) echo "Unknown argument: $1" >&2; usage; exit 2 ;;
  esac
done

echo "SROF_BOOTSTRAP_MODE=$MODE"
echo "HOST=$(hostname)"
echo "REMOTE_USER=$REMOTE_USER"
echo "SSH_ACTIVE=$(systemctl is-active ssh 2>/dev/null || systemctl is-active sshd 2>/dev/null || true)"
echo "SSH_VERSION=$(ssh -V 2>&1 || true)"
echo "DOCKER_VERSION=$(docker --version 2>/dev/null || true)"
echo "LISTENERS:"
ss -ltn 2>/dev/null | head -40 || true

if [ "$MODE" != "apply" ]; then
  echo "PLAN_ONLY=PASS"
  exit 0
fi

if [ "$(id -u)" -ne 0 ]; then
  echo "ERROR: --apply must be run as root/sudo" >&2
  exit 3
fi

if ! id "$REMOTE_USER" >/dev/null 2>&1; then
  useradd --create-home --shell /bin/bash "$REMOTE_USER"
fi

install -d -m 0700 -o "$REMOTE_USER" -g "$REMOTE_USER" "/home/$REMOTE_USER/.ssh"
install -d -m 0750 -o "$REMOTE_USER" -g "$REMOTE_USER" "/var/lib/scientiam/remote-ops"
install -d -m 0750 -o "$REMOTE_USER" -g "$REMOTE_USER" "/var/log/scientiam/remote-ops"

echo "ACCOUNT_READY=YES"
echo "NEXT=install an approved public key, verify second-session login, then apply reviewed sshd/sudoers snippets separately"
echo "CURRENT_ACCESS_NOT_MODIFIED=YES"
