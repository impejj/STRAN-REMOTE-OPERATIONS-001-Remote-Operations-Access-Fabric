#!/usr/bin/env bash
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
COMPOSE="$REPO_ROOT/deploy/native-auth/compose.yml"
ENV_FILE="/etc/scientiam/remote-ops/keycloak.env"
REALM="scientiam-srof"
KC_CONTAINER="${SROF_KEYCLOAK_CONTAINER:-native-auth-keycloak-1}"

cleanup() {
  unset FOUNDER_PASS FOUNDER_PASS_2
  if [ -n "${PAYLOAD_FILE:-}" ] && [ -f "${PAYLOAD_FILE:-}" ]; then
    rm -f "$PAYLOAD_FILE"
  fi
  docker exec "$KC_CONTAINER" rm -f /tmp/srof-founder-password.json >/dev/null 2>&1 || true
}
trap cleanup EXIT

read -r -p "Founder login email: " FOUNDER_EMAIL
if ! [[ "$FOUNDER_EMAIL" =~ ^[^[:space:]@]+@[^[:space:]@]+\.[^[:space:]@]+$ ]]; then
  echo "BLOCKED: invalid email" >&2
  exit 10
fi

read -r -s -p "New Founder OAuth password (minimum 16 characters): " FOUNDER_PASS
echo
read -r -s -p "Repeat new Founder OAuth password: " FOUNDER_PASS_2
echo

if [ "$FOUNDER_PASS" != "$FOUNDER_PASS_2" ] || [ "${#FOUNDER_PASS}" -lt 16 ]; then
  echo "BLOCKED: passwords differ or are shorter than 16 characters" >&2
  exit 11
fi

if ! docker ps --format '{{.Names}}' | grep -Fxq "$KC_CONTAINER"; then
  echo "BLOCKED: Keycloak container not running: $KC_CONTAINER" >&2
  exit 12
fi

echo "KEYCLOAK_CONTAINER=PASS"

# Preferred recovery path: authenticate entirely inside the running Keycloak
# container using the bootstrap credentials already injected into its environment.
# This avoids reading /etc/scientiam/remote-ops/keycloak.env from the host and
# therefore does not require sudo when the operator can access Docker.
docker exec "$KC_CONTAINER" sh -lc '
  export KC_CLI_PASSWORD="$KC_BOOTSTRAP_ADMIN_PASSWORD"
  /opt/keycloak/bin/kcadm.sh config credentials \
    --server http://localhost:8080 \
    --realm master \
    --user "$KC_BOOTSTRAP_ADMIN_USERNAME" >/dev/null
'
echo "KEYCLOAK_ADMIN_LOGIN=PASS"

USER_JSON="$(mktemp)"
docker exec "$KC_CONTAINER" /opt/keycloak/bin/kcadm.sh get users \
  -r "$REALM" -q "username=$FOUNDER_EMAIL" > "$USER_JSON"

USER_ID="$(python3 - "$USER_JSON" "$FOUNDER_EMAIL" <<'PY'
import json,sys
rows=json.load(open(sys.argv[1],encoding="utf-8"))
email=sys.argv[2]
for row in rows:
    if row.get("username")==email:
        print(row.get("id",""))
        raise SystemExit(0)
raise SystemExit(1)
PY
)"
rm -f "$USER_JSON"

if [ -z "$USER_ID" ]; then
  echo "BLOCKED: Founder user not found" >&2
  exit 13
fi
echo "FOUNDER_USER_PRESENT=PASS"

# Build the credential representation outside the command line so the new
# password is not exposed through process arguments.
PAYLOAD_FILE="$(mktemp)"
chmod 600 "$PAYLOAD_FILE"
export FOUNDER_PASS
python3 - <<'PY' > "$PAYLOAD_FILE"
import json, os
print(json.dumps({
    "type": "password",
    "value": os.environ["FOUNDER_PASS"],
    "temporary": False,
}))
PY
unset FOUNDER_PASS FOUNDER_PASS_2

docker cp "$PAYLOAD_FILE" "$KC_CONTAINER:/tmp/srof-founder-password.json" >/dev/null
rm -f "$PAYLOAD_FILE"
PAYLOAD_FILE=""

# Keycloak Admin REST:
# PUT /admin/realms/{realm}/users/{user-id}/reset-password
docker exec "$KC_CONTAINER" /opt/keycloak/bin/kcadm.sh update \
  "users/$USER_ID/reset-password" \
  -r "$REALM" \
  -f /tmp/srof-founder-password.json \
  -n >/dev/null
docker exec "$KC_CONTAINER" rm -f /tmp/srof-founder-password.json >/dev/null

echo "FOUNDER_PASSWORD_RESET=PASS"

docker exec "$KC_CONTAINER" /opt/keycloak/bin/kcadm.sh delete \
  "attack-detection/brute-force/users/$USER_ID" \
  -r "$REALM" >/dev/null 2>&1 || true
echo "FOUNDER_BRUTE_FORCE_STATE_CLEARED=PASS"

docker exec "$KC_CONTAINER" /opt/keycloak/bin/kcadm.sh update \
  "users/$USER_ID" \
  -r "$REALM" \
  -s 'requiredActions=["CONFIGURE_TOTP"]' >/dev/null
echo "FOUNDER_TOTP_REQUIRED=PASS"

CREDS_JSON="$(mktemp)"
docker exec "$KC_CONTAINER" /opt/keycloak/bin/kcadm.sh get \
  "users/$USER_ID/credentials" -r "$REALM" > "$CREDS_JSON"
python3 - "$CREDS_JSON" <<'PY'
import json,sys
creds=json.load(open(sys.argv[1],encoding="utf-8"))
types=sorted({str(x.get("type")) for x in creds if x.get("type")})
assert "password" in types, types
print("FOUNDER_CREDENTIAL_TYPES="+",".join(types))
print("FOUNDER_PASSWORD_CREDENTIAL=PASS")
PY
rm -f "$CREDS_JSON"

echo "SECRETS_PRINTED=NO"
echo "FOUNDER_PASSWORD_RECOVERY=PASS"
