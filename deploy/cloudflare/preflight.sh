#!/usr/bin/env bash
set -euo pipefail

PUBLIC_HOSTNAME="${SROF_PUBLIC_HOSTNAME:-}"
GATEWAY_PORT="${SROF_GATEWAY_PORT:-8765}"

echo "=== SROF CLOUDFLARE PREFLIGHT ==="
echo "HOST=$(hostname -s)"
echo "TIME=$(date -Is)"

command -v systemctl >/dev/null
command -v ss >/dev/null
command -v curl >/dev/null

systemctl is-active --quiet scientiam-remote-ops-gateway.service
echo "SROF_GATEWAY_SERVICE=PASS"

if ss -ltn | grep -Fq "127.0.0.1:${GATEWAY_PORT}"; then
  echo "SROF_LOOPBACK_BIND=PASS"
else
  echo "SROF_LOOPBACK_BIND=FAIL" >&2
  exit 10
fi

if command -v cloudflared >/dev/null; then
  echo "CLOUDFLARED=$(command -v cloudflared)"
  cloudflared --version || true
else
  echo "CLOUDFLARED=MISSING"
  exit 11
fi

if systemctl list-unit-files cloudflared.service >/dev/null 2>&1; then
  systemctl is-active cloudflared.service || true
  systemctl is-enabled cloudflared.service || true
else
  echo "CLOUDFLARED_SERVICE=NOT_INSTALLED"
fi

if [[ -n "$PUBLIC_HOSTNAME" ]]; then
  echo "PUBLIC_HOSTNAME=$PUBLIC_HOSTNAME"
  echo "NOTE=external Access/OAuth test requires Cloudflare configuration"
else
  echo "PUBLIC_HOSTNAME=UNSET"
fi

echo "SROF_CLOUDFLARE_PREFLIGHT=PASS_LOCAL"
