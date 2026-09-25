#!/usr/bin/env bash
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
COMPOSE="$REPO_ROOT/deploy/native-auth/compose.yml"
ENV_FILE="/etc/scientiam/remote-ops/keycloak.env"
AUTH_HOST="${SROF_AUTH_HOSTNAME:-auth.scientiam.com.ar}"
AUTH_EDGE="http://127.0.0.1:8097"
KEYCLOAK_HEALTH="http://127.0.0.1:9006/health/ready"
DISCOVERY_PATH="/realms/scientiam-srof/.well-known/openid-configuration"
AUTH_PATH="/realms/scientiam-srof/protocol/openid-connect/auth?client_id=srof-openai-responses-cli&redirect_uri=http%3A%2F%2F127.0.0.1%3A8766%2Fcallback&response_type=code&scope=openid%20srof%3Aread&state=DIAGNOSTIC&code_challenge=E9Melhoa2OwvFrEMTJguCHaoeK1t8URWbuGJSstw-cM&code_challenge_method=S256"

if [ "$(id -u)" -ne 0 ]; then
  echo "BLOCKED: run with sudo/root" >&2
  exit 3
fi

echo "=== STRAN/SROF · AUTH 504 DIAGNOSTIC ==="
echo "HOST=$(hostname -s)"
echo "TIME=$(date -Is)"
echo "AUTH_HOST=$AUTH_HOST"
echo

echo "=== SERVICES ==="
systemctl is-active cloudflared-scientiam-srof.service || true
docker compose --env-file "$ENV_FILE" -f "$COMPOSE" ps auth-edge keycloak
echo

echo "=== LISTENERS ==="
ss -ltnp | grep -E ':(8096|8097|9006|8765)\\b' || true
echo

probe() {
  name="$1"
  url="$2"
  host_header="${3:-}"
  headers="$(mktemp)"
  body="$(mktemp)"
  if [ -n "$host_header" ]; then
    code="$(curl -sS --max-time 15 -H "Host: $host_header" -D "$headers" -o "$body" -w '%{http_code}' "$url" || true)"
  else
    code="$(curl -sS --max-time 15 -D "$headers" -o "$body" -w '%{http_code}' "$url" || true)"
  fi
  echo "${name}_HTTP=${code:-CURL_ERROR}"
  awk 'BEGIN{IGNORECASE=1} /^server:|^cf-ray:|^location:/{gsub(/\r/,""); print}' "$headers" | sed "s/^/${name}_/"
  echo "${name}_BODY_BYTES=$(wc -c < "$body")"
  rm -f "$headers" "$body"
}

echo "=== LOCAL KEYCLOAK HEALTH ==="
probe KEYCLOAK_HEALTH "$KEYCLOAK_HEALTH"
echo

echo "=== LOCAL AUTH EDGE ==="
probe LOCAL_DISCOVERY "$AUTH_EDGE$DISCOVERY_PATH" "$AUTH_HOST"
probe LOCAL_AUTH "$AUTH_EDGE$AUTH_PATH" "$AUTH_HOST"
echo

echo "=== PUBLIC AUTH ROUTE ==="
probe PUBLIC_DISCOVERY "https://$AUTH_HOST$DISCOVERY_PATH"
probe PUBLIC_AUTH "https://$AUTH_HOST$AUTH_PATH"
echo

echo "=== RECENT LOGS ==="
docker compose --env-file "$ENV_FILE" -f "$COMPOSE" logs --since 10m --tail=160 auth-edge keycloak || true
echo
journalctl -u cloudflared-scientiam-srof.service --since '-10 min' --no-pager -o cat | tail -160 || true

echo
echo "AUTH_504_DIAGNOSTIC=COMPLETE"
echo "NO_CONFIGURATION_CHANGED=YES"
echo "TOKEN_CONTENT_READ=NO"
echo "DCP_USED=NO"
echo "GITHUB_ACTIONS_TRANSPORT=NO"
