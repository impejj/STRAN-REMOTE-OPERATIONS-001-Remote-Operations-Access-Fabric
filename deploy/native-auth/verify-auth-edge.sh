#!/usr/bin/env bash
set -euo pipefail

echo "=== STRAN/SROF · AUTH EDGE LOCAL VERIFY ==="
echo "HOST=$(hostname -s)"
echo "TIME=$(date -Is)"

BASE="http://127.0.0.1:8097"
HOST_HDR="auth.scientiam.com.ar"

echo
echo "=== OIDC DISCOVERY THROUGH EDGE ==="
DISC="$(mktemp)"
trap 'rm -f "$DISC"' EXIT
curl -fsS -H "Host: $HOST_HDR"   "$BASE/realms/scientiam-srof/.well-known/openid-configuration" > "$DISC"

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
  code="$(curl -sS -o /dev/null -w '%{http_code}' -H "Host: $HOST_HDR" "$BASE$path")"
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
