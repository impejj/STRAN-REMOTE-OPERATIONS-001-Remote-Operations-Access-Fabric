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

read -r -p "Founder login email to verify: " FOUNDER_EMAIL

KC=(docker compose --env-file "$ENV_FILE" -f "$COMPOSE" exec -T keycloak /opt/keycloak/bin/kcadm.sh)
"${KC[@]}" config credentials --server http://localhost:8080 --realm master --user "$KC_BOOTSTRAP_ADMIN_USERNAME" --password "$KC_BOOTSTRAP_ADMIN_PASSWORD" >/dev/null

USER_JSON="$(mktemp)"
CREDS_JSON="$(mktemp)"
trap 'rm -f "$USER_JSON" "$CREDS_JSON"' EXIT

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
"${KC[@]}" get "users/$USER_ID/credentials" -r "$REALM" > "$CREDS_JSON"

python3 - "$USER_JSON" "$CREDS_JSON" "$FOUNDER_EMAIL" <<'PY'
import json,sys
users=json.load(open(sys.argv[1],encoding="utf-8"))
creds=json.load(open(sys.argv[2],encoding="utf-8"))
email=sys.argv[3]
user=next(x for x in users if x.get("username")==email)
actions=user.get("requiredActions") or []
types=sorted({str(x.get("type")) for x in creds if x.get("type")})
print("FOUNDER_USER_PRESENT=PASS")
print("FOUNDER_ENABLED="+str(bool(user.get("enabled"))).lower())
print("FOUNDER_REQUIRED_ACTIONS="+(",".join(actions) if actions else "NONE"))
print("FOUNDER_CREDENTIAL_TYPES="+(",".join(types) if types else "NONE"))
if "CONFIGURE_TOTP" in actions:
    print("FOUNDER_TOTP_ENROLLED=NO")
    raise SystemExit(20)
if "otp" not in types:
    print("FOUNDER_TOTP_ENROLLED=NO")
    raise SystemExit(21)
print("FOUNDER_TOTP_ENROLLED=PASS")
PY

echo "SECRETS_PRINTED=NO"
echo "FOUNDER_AUTH_HUMAN_GATE=PASS"
