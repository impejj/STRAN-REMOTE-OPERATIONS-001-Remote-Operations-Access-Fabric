#!/usr/bin/env bash
set -euo pipefail

fail=0
check() {
  local name="$1"; shift
  if "$@" >/dev/null 2>&1; then
    echo "PASS $name"
  else
    echo "FAIL $name"
    fail=1
  fi
}

echo "SROF_PREFLIGHT_HOST=$(hostname)"
check "ssh client" command -v ssh
check "scp" command -v scp
check "rsync" command -v rsync
check "python3" command -v python3
check "git" command -v git
check "systemctl" command -v systemctl

if command -v docker >/dev/null 2>&1; then
  echo "PASS docker"
else
  echo "INFO docker unavailable on this host"
fi

echo "SSH_VERSION=$(ssh -V 2>&1 || true)"
echo "PYTHON_VERSION=$(python3 --version 2>&1 || true)"
echo "GIT_VERSION=$(git --version 2>&1 || true)"
echo "LISTENERS_BEGIN"
ss -ltn 2>/dev/null | head -60 || true
echo "LISTENERS_END"

exit "$fail"
