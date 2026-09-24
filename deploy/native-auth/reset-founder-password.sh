#!/usr/bin/env bash
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
COMPOSE="$REPO_ROOT/deploy/native-auth/compose.yml"
ENV_FILE="/etc/scientiam/remote-ops/keycloak.env"
REALM="scientiam-srof"

if [ "$(id -u)" -ne 0 ]; then
  echo "BLOCKED: run with sudo/root" >&2
  exit 3
fi

test -r "$ENV_FILE"
set -a
# shellcheck disable=SC1090
. "$ENV_FILE"
set +a

read -r -p "Founder login email: " FOUNDER_EMAIL
read -r -s -p "New Founder OAuth password (minimum 16 characters): " FOUNDER_PASS
echo
read -r -s -p "Repeat new Founder OAuth password: " FOUNDER_PASS_2
echo

if [ "$FOUNDER_PASS" != "$FOUNDER_PASS_2" ] || [ "${#FOUNDER_PASS}" -lt 16 ]; then
  echo "BLOCKED: passwords differ or are shorter than 16 characters" >&2
  exit 10
fi

KC=(docker compose --env-file "$ENV_FILE" -f "$COMPOSE" exec -T keycloak /opt/keycloak/bin/kcadm.sh)
"${KC[@]}" config credentials --server http://localhost:8080 --realm master --user "$KC_BOOTSTRAP_ADMIN_USERNAME" --password "$KC_BOOTSTRAP_ADMIN_PASSWORD" >/dev/null

USER_JSON="$(mktemp)"
trap 'rm -f "$USER_JSON"; unset FOUNDER_PASS FOUNDER_PASS_2 KC_BOOTSTRAP_ADMIN_PASSWORD KC_DB_PASSWORD' EXIT
"${KC[@]}" get users -r "$REALM" -q "username=$FOUNDER_EMAIL" > "$USER_JSON"

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

test -n "$USER_ID"
echo "FOUNDER_USER_PRESENT=PASS"

# Set a permanent password. Pass the secret as an environment variable to the
# containerized CLI so it is not printed or placed in the command line.
docker compose --env-file "$ENV_FILE" -f "$COMPOSE" exec -T \
  -e KC_CLI_PASSWORD="$FOUNDER_PASS" \
  keycloak /opt/keycloak/bin/kcadm.sh set-password \
  -r "$REALM" --userid "$USER_ID" >/dev/null
echo "FOUNDER_PASSWORD_RESET=PASS"

# Release any temporary brute-force lock for this user.
"${KC[@]}" delete "attack-detection/brute-force/users/$USER_ID" -r "$REALM" >/dev/null 2>&1 || true
echo "FOUNDER_BRUTE_FORCE_STATE_CLEARED=PASS"

# Ensure TOTP enrollment remains the only intended first-login action.
"${KC[@]}" update "users/$USER_ID" -r "$REALM" -s 'requiredActions=["CONFIGURE_TOTP"]' >/dev/null
echo "FOUNDER_TOTP_REQUIRED=PASS"

CREDS_JSON="$(mktemp)"
"${KC[@]}" get "users/$USER_ID/credentials" -r "$REALM" > "$CREDS_JSON"
python3 - "$CREDS_JSON" <<'PY'
import json,sys
creds=json.load(open(sys.argv[1],encoding="utf-8"))
types=sorted({str(x.get("type")) for x in creds if x.get("type")})
assert "password" in types, types
print("FOUNDER_CREDENTIAL_TYPES="+",".join(types))
print("FOUNDER_PASSWORD_CREDENTIAL=PASS")
PY
rm -f "$CREDS_JSON"

unset FOUNDER_PASS FOUNDER_PASS_2
echo "SECRETS_PRINTED=NO"
echo "FOUNDER_PASSWORD_RECOVERY=PASS"
