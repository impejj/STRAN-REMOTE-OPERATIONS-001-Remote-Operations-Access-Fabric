#!/usr/bin/env bash
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"

echo "=== STRAN/SROF · NATIVE AUTH ASSET VALIDATION ==="
echo "HOST=$(hostname -s)"
echo "TIME=$(date -Is)"

echo
echo "=== BASH SYNTAX ==="
for f in "$REPO_ROOT"/deploy/native-auth/*.sh; do
  bash -n "$f"
  echo "BASH_SYNTAX=PASS:$f"
done

echo
echo "=== JSON ==="
python3 -m json.tool "$REPO_ROOT/deploy/native-auth/realm-scientiam-srof.json" >/dev/null
echo "REALM_JSON=PASS"

echo
echo "=== PYTHON SYNTAX ==="
python3 -m py_compile \
  "$REPO_ROOT/gateway/src/srof_gateway/keycloak_auth.py" \
  "$REPO_ROOT/gateway/src/srof_gateway/server.py" \
  "$REPO_ROOT/gateway/src/srof_gateway/ssh_runner.py"
echo "PYTHON_SYNTAX=PASS"

echo
echo "=== COMPOSE MODEL ==="
docker compose \
  --env-file "$REPO_ROOT/deploy/native-auth/keycloak.env.example" \
  -f "$REPO_ROOT/deploy/native-auth/compose.yml" \
  config --quiet
echo "COMPOSE_CONFIG=PASS"

echo
echo "NATIVE_AUTH_ASSETS=PASS"
echo "NO_CONFIGURATION_CHANGED=YES"
