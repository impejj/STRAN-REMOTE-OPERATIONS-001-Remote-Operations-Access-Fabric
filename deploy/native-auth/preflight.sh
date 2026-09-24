#!/usr/bin/env bash
set -euo pipefail

echo "=== STRAN/SROF · NATIVE OAUTH PREFLIGHT ==="
echo "HOST=$(hostname -s)"
echo "TIME=$(date -Is)"

test "$(hostname -s)" = "profesys-scientiam"
command -v docker >/dev/null
command -v curl >/dev/null
command -v openssl >/dev/null
command -v ss >/dev/null

docker --version
docker compose version

for port in 8096 9006; do
  if ss -ltn | awk '{print $4}' | grep -Eq "(^|:)$port$"; then
    echo "PORT_${port}=IN_USE"
  else
    echo "PORT_${port}=FREE"
  fi
done

if ss -ltn | grep -Fq "127.0.0.1:8765"; then
  echo "SROF_LOOPBACK_BIND=PASS"
else
  echo "SROF_LOOPBACK_BIND=FAIL"
  exit 21
fi

if ss -ltn | grep -Eq "0\.0\.0\.0:8765|\[::\]:8765"; then
  echo "SROF_EXTERNAL_BIND=FAIL"
  exit 22
else
  echo "SROF_EXTERNAL_BIND=NONE"
fi

systemctl is-active --quiet cloudflared-scientiam-srof.service
echo "DEDICATED_TUNNEL_CONNECTOR=PASS"

echo "KEYCLOAK_TARGET=127.0.0.1:8096"
echo "KEYCLOAK_HEALTH_TARGET=127.0.0.1:9006"
echo "AUTH_PUBLIC_HOSTNAME=auth.scientiam.com.ar"
echo "MCP_PUBLIC_HOSTNAME=srof.scientiam.com.ar"
echo "NATIVE_OAUTH_PREFLIGHT=PASS"
echo "NO_CONFIGURATION_CHANGED=YES"
