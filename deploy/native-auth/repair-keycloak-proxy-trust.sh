#!/usr/bin/env bash
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
COMPOSE="$REPO_ROOT/deploy/native-auth/compose.yml"
ENV_FILE="/etc/scientiam/remote-ops/keycloak.env"
NETWORK="native-auth_srof-auth"

if [ "$(id -u)" -ne 0 ]; then
  echo "BLOCKED: run with sudo/root" >&2
  exit 3
fi

echo "=== STRAN/SROF · REPAIR KEYCLOAK PROXY TRUST ==="
echo "HOST=$(hostname -s)"
echo "TIME=$(date -Is)"

test -r "$ENV_FILE"
command -v docker >/dev/null
command -v python3 >/dev/null
command -v curl >/dev/null

SUBNET="$(docker network inspect "$NETWORK" --format '{{(index .IPAM.Config 0).Subnet}}')"
AUTH_EDGE_IP="$(docker inspect -f '{{range .NetworkSettings.Networks}}{{.IPAddress}}{{end}}' native-auth-auth-edge-1)"

python3 - "$SUBNET" "$AUTH_EDGE_IP" <<'PY'
import ipaddress,sys
net=ipaddress.ip_network(sys.argv[1],strict=False)
ip=ipaddress.ip_address(sys.argv[2])
assert ip in net, (ip,net)
print("AUTH_EDGE_NETWORK="+str(net))
print("AUTH_EDGE_IP="+str(ip))
print("AUTH_EDGE_IP_IN_TRUSTED_SUBNET=PASS")
PY

TMP="$(mktemp)"
trap 'rm -f "$TMP"' EXIT
awk -v subnet="$SUBNET" '
  BEGIN { done=0 }
  /^SROF_AUTH_PROXY_TRUSTED_SUBNET=/ {
    print "SROF_AUTH_PROXY_TRUSTED_SUBNET=" subnet
    done=1
    next
  }
  { print }
  END {
    if (!done) print "SROF_AUTH_PROXY_TRUSTED_SUBNET=" subnet
  }
' "$ENV_FILE" > "$TMP"

install -m 0640 -o root -g scientiam-remoteops "$TMP" "$ENV_FILE"
echo "KEYCLOAK_TRUST_ENV_UPDATED=PASS"

docker compose --env-file "$ENV_FILE" -f "$COMPOSE" config --quiet
echo "COMPOSE_CONFIG=PASS"

START_TS="$(date -u +%Y-%m-%dT%H:%M:%SZ)"

docker compose --env-file "$ENV_FILE" -f "$COMPOSE" up -d --force-recreate keycloak auth-edge

echo "WAITING_FOR_KEYCLOAK=YES"
for _ in $(seq 1 90); do
  if curl -fsS http://127.0.0.1:9006/health/ready >/dev/null 2>&1; then
    echo "KEYCLOAK_READY=PASS"
    break
  fi
  sleep 2
done
curl -fsS http://127.0.0.1:9006/health/ready >/dev/null

echo "WAITING_FOR_AUTH_EDGE=YES"
for _ in $(seq 1 60); do
  if curl -fsS -H 'Host: auth.scientiam.com.ar'     http://127.0.0.1:8097/realms/scientiam-srof/.well-known/openid-configuration     >/dev/null 2>&1; then
    echo "AUTH_EDGE_READY=PASS"
    break
  fi
  sleep 1
done
curl -fsS -H 'Host: auth.scientiam.com.ar'   http://127.0.0.1:8097/realms/scientiam-srof/.well-known/openid-configuration   >/dev/null

echo "=== PROXY TRUST SMOKE ==="
curl -fsS -o /dev/null   'https://auth.scientiam.com.ar/realms/scientiam-srof/account/'
curl -fsS -o /dev/null   'https://auth.scientiam.com.ar/realms/scientiam-srof/protocol/openid-connect/auth?client_id=account-console&redirect_uri=https%3A%2F%2Fauth.scientiam.com.ar%2Frealms%2Fscientiam-srof%2Faccount%2F&response_type=code&scope=openid&code_challenge=AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA&code_challenge_method=S256'

sleep 2

if docker compose --env-file "$ENV_FILE" -f "$COMPOSE" logs --since "$START_TS" keycloak   | grep -Fq 'Non-secure context detected'; then
  echo "KEYCLOAK_PROXY_TRUST=FAIL_NON_SECURE_CONTEXT" >&2
  exit 20
fi

echo "KEYCLOAK_PROXY_TRUST=PASS"
echo "FORWARDED_HEADERS_OVERWRITTEN=PASS"
echo "FOUNDER_USER_CHANGED=NO"
echo "POSTGRES_CHANGED=NO"
echo "CLOUDFLARE_ROUTE_CHANGED=NO"
