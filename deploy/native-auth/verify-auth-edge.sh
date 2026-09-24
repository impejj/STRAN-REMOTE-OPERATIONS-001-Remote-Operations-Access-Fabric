#!/usr/bin/env bash
set -euo pipefail

echo "=== STRAN/SROF · AUTH EDGE LOCAL VERIFY ==="
echo "HOST=$(hostname -s)"
echo "TIME=$(date -Is)"

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
COMPOSE="$REPO_ROOT/deploy/native-auth/compose.yml"
ENV_FILE="/etc/scientiam/remote-ops/keycloak.env"
BASE="http://127.0.0.1:8097"
HOST_HDR="auth.scientiam.com.ar"

diagnose() {
  echo
  echo "=== AUTH EDGE DIAGNOSTICS ===" >&2
  docker compose --env-file "$ENV_FILE" -f "$COMPOSE" ps auth-edge keycloak >&2 || true
  echo >&2
  docker compose --env-file "$ENV_FILE" -f "$COMPOSE" logs --tail=80 auth-edge >&2 || true
  echo >&2
  docker compose --env-file "$ENV_FILE" -f "$COMPOSE" exec -T auth-edge nginx -t >&2 || true
}

echo
echo "=== WAIT AUTH EDGE READY ==="
READY=0
for i in $(seq 1 30); do
  if curl -fsS --max-time 3 -H "Host: $HOST_HDR"     "$BASE/realms/scientiam-srof/.well-known/openid-configuration"     >/dev/null 2>&1; then
    READY=1
    echo "AUTH_EDGE_READY=PASS attempt=$i"
    break
  fi
  sleep 1
done

if [ "$READY" -ne 1 ]; then
  echo "AUTH_EDGE_READY=FAIL" >&2
  diagnose
  exit 20
fi

echo
echo "=== OIDC DISCOVERY THROUGH EDGE ==="
DISC="$(mktemp)"
trap 'rm -f "$DISC"' EXIT
curl -fsS --max-time 5 -H "Host: $HOST_HDR"   "$BASE/realms/scientiam-srof/.well-known/openid-configuration" > "$DISC"

python3 - "$DISC" <<'PY'
import json,sys
d=json.load(open(sys.argv[1],encoding="utf-8"))
assert d.get("issuer")=="https://auth.scientiam.com.ar/realms/scientiam-srof"
assert "S256" in d.get("code_challenge_methods_supported",[])
print("AUTH_EDGE_SROF_REALM=PASS")
print("AUTH_EDGE_PKCE=PASS")
PY

check_404() {
  name="$1"
  path="$2"
  code="$(curl -sS --max-time 5 -o /dev/null -w '%{http_code}' -H "Host: $HOST_HDR" "$BASE$path")"
  echo "$name=$code"
  [ "$code" = "404" ]
}

check_404 AUTH_EDGE_ADMIN_BLOCK /admin/master/console/
check_404 AUTH_EDGE_MASTER_REALM_BLOCK /realms/master/.well-known/openid-configuration
check_404 AUTH_EDGE_OTHER_REALM_BLOCK /realms/not-allowed/.well-known/openid-configuration
check_404 AUTH_EDGE_ROOT_BLOCK /

echo
echo "AUTH_EDGE_LOCAL=PASS"
echo "PUBLIC_ROUTE_CREATED=NO"
echo "DCP_USED=NO"
echo "GITHUB_ACTIONS_TRANSPORT=NO"
