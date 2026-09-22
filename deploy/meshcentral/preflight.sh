#!/usr/bin/env bash
set -euo pipefail

: "${MESH_HOSTNAME:?MESH_HOSTNAME required}"
: "${MESH_BIND_IP:?MESH_BIND_IP required}"

command -v docker >/dev/null
docker compose version >/dev/null

if ! ip -br addr | grep -Fq "$MESH_BIND_IP"; then
  echo "ERROR: MESH_BIND_IP $MESH_BIND_IP is not present on this host" >&2
  exit 2
fi

for port in 8443 8088; do
  if ss -ltn | awk '{print $4}' | grep -Eq "[:.]$port$"; then
    echo "ERROR: port $port already in use" >&2
    exit 3
  fi
done

echo "MESHCENTRAL_PREFLIGHT=PASS"
echo "HOSTNAME=$MESH_HOSTNAME"
echo "BIND_IP=$MESH_BIND_IP"
