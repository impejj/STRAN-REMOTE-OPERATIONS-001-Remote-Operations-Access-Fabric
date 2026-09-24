#!/usr/bin/env bash
set -euo pipefail

MODE="${1:-plan}"
case "$MODE" in
  plan|apply) ;;
  *) echo "usage: $0 [plan|apply]" >&2; exit 2 ;;
esac

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
COMPOSE="$REPO_ROOT/deploy/native-auth/compose.yml"
ENV_FILE="/etc/scientiam/remote-ops/keycloak.env"

echo "=== STRAN/SROF · PREPARE NATIVE OAUTH ==="
echo "MODE=$MODE"
echo "HOST=$(hostname -s)"
echo "TIME=$(date -Is)"

bash "$REPO_ROOT/deploy/native-auth/preflight.sh"

if [ "$MODE" = "plan" ]; then
  echo "PLAN_ONLY=PASS"
  exit 0
fi

if [ "$(id -u)" -ne 0 ]; then
  echo "BLOCKED: apply requires sudo/root" >&2
  exit 3
fi

install -d -m 0750 -o root -g scientiam-remoteops /etc/scientiam/remote-ops

if [ ! -f "$ENV_FILE" ]; then
  DB_PASS="$(openssl rand -hex 32)"
  ADMIN_PASS="$(openssl rand -hex 32)"
  umask 077
  cat > "$ENV_FILE" <<EOF
KC_DB_USERNAME=keycloak
KC_DB_PASSWORD=$DB_PASS
KC_BOOTSTRAP_ADMIN_USERNAME=srof-admin
KC_BOOTSTRAP_ADMIN_PASSWORD=$ADMIN_PASS
EOF
  unset DB_PASS ADMIN_PASS
  chown root:scientiam-remoteops "$ENV_FILE"
  chmod 0640 "$ENV_FILE"
  echo "KEYCLOAK_ENV_CREATED=YES"
  echo "KEYCLOAK_BOOTSTRAP_ADMIN_SECRET=GENERATED_LOCAL_NOT_PRINTED"
else
  echo "KEYCLOAK_ENV_CREATED=NO_REUSED"
fi

docker compose --env-file "$ENV_FILE" -f "$COMPOSE" pull
docker compose --env-file "$ENV_FILE" -f "$COMPOSE" up -d

echo "WAITING_FOR_KEYCLOAK_READY=YES"
READY=0
for _ in $(seq 1 90); do
  if curl -fsS http://127.0.0.1:9006/health/ready >/dev/null 2>&1; then
    READY=1
    break
  fi
  sleep 2
done
if [ "$READY" -ne 1 ]; then
  echo "KEYCLOAK_READY=FAIL" >&2
  docker compose --env-file "$ENV_FILE" -f "$COMPOSE" ps
  exit 11
fi
echo "KEYCLOAK_READY=PASS"

curl -fsS http://127.0.0.1:8096/realms/scientiam-srof/.well-known/openid-configuration \
  | python3 -c 'import json,sys; d=json.load(sys.stdin); print("ISSUER="+d.get("issuer","")); print("PKCE_S256="+str("S256" in d.get("code_challenge_methods_supported",[])).lower()); print("CIMD="+str(bool(d.get("client_id_metadata_document_supported"))).lower())'

echo "KEYCLOAK_LOCAL_DEPLOYMENT=PASS"
echo "PUBLIC_ROUTE_CREATED=NO"
echo "SROF_OAUTH_ENABLED=NO"
