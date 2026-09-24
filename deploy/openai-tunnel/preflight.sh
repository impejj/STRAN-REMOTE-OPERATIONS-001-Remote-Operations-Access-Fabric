#!/usr/bin/env bash
set -euo pipefail

GATEWAY_URL="${SROF_GATEWAY_URL:-http://127.0.0.1:8765/mcp}"
PROFILE="${SROF_TUNNEL_PROFILE:-srof-chatgpt}"
ENV_FILE="/etc/scientiam/remote-ops/openai-tunnel.env"

echo "=== SROF CHATGPT EXPOSURE PREFLIGHT ==="
echo "HOST=$(hostname -s)"
echo "TIME=$(date -Is)"

command -v systemctl >/dev/null
command -v curl >/dev/null

systemctl is-active --quiet scientiam-remote-ops-gateway.service
echo "SROF_GATEWAY_SERVICE=PASS"

if ss -ltn | grep -Fq '127.0.0.1:8765'; then
  echo "SROF_LOOPBACK_BIND=PASS"
else
  echo "SROF_LOOPBACK_BIND=FAIL" >&2
  exit 10
fi

if command -v tunnel-client >/dev/null; then
  echo "TUNNEL_CLIENT=$(command -v tunnel-client)"
  tunnel-client --version || true
else
  echo "TUNNEL_CLIENT=MISSING"
  exit 11
fi

if [[ -r "$ENV_FILE" ]]; then
  echo "TUNNEL_ENV_FILE=PASS"
else
  echo "TUNNEL_ENV_FILE=MISSING_OR_UNREADABLE"
  exit 12
fi

# Do not print the key.
if grep -Eq '^CONTROL_PLANE_API_KEY=.+$' "$ENV_FILE"; then
  echo "CONTROL_PLANE_API_KEY=PRESENT_REDACTED"
else
  echo "CONTROL_PLANE_API_KEY=MISSING"
  exit 13
fi

echo "GATEWAY_URL=$GATEWAY_URL"
echo "PROFILE=$PROFILE"

echo "NEXT=tunnel-client doctor --profile $PROFILE --explain"
echo "SROF_CHATGPT_EXPOSURE_PREFLIGHT=PASS"
