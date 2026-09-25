#!/usr/bin/env bash
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
COMPOSE="$REPO_ROOT/deploy/native-auth/compose.yml"
ENV_FILE="/etc/scientiam/remote-ops/keycloak.env"
REALM="scientiam-srof"
CLIENT_ID="${SROF_OPENAI_CLIENT_ID:-srof-openai-responses-cli}"
REDIRECT_URI="${SROF_OPENAI_REDIRECT_URI:-http://127.0.0.1:8766/callback}"

if [ "$(id -u)" -ne 0 ]; then
  echo "BLOCKED: run with sudo/root" >&2
  exit 3
fi

test -r "$ENV_FILE"
set -a
# shellcheck disable=SC1090
. "$ENV_FILE"
set +a

KC=(docker compose --env-file "$ENV_FILE" -f "$COMPOSE" exec -T keycloak /opt/keycloak/bin/kcadm.sh)
"${KC[@]}" config credentials   --server http://localhost:8080   --realm master   --user "$KC_BOOTSTRAP_ADMIN_USERNAME"   --password "$KC_BOOTSTRAP_ADMIN_PASSWORD" >/dev/null

TMP="$(mktemp)"
trap 'rm -f "$TMP"' EXIT

python3 - "$TMP" "$CLIENT_ID" "$REDIRECT_URI" <<'PY'
import json,sys
path,client_id,redirect_uri=sys.argv[1:]
payload={
  "clientId": client_id,
  "name": "SCIENTIAM SROF OpenAI Responses CLI",
  "description": "Native loopback PKCE client for Founder-authenticated OpenAI Responses -> SROF P0.",
  "enabled": True,
  "protocol": "openid-connect",
  "publicClient": True,
  "standardFlowEnabled": True,
  "implicitFlowEnabled": False,
  "directAccessGrantsEnabled": False,
  "serviceAccountsEnabled": False,
  "consentRequired": True,
  "fullScopeAllowed": False,
  "redirectUris": [redirect_uri],
  "webOrigins": [],
  "attributes": {
    "pkce.code.challenge.method": "S256"
  },
  "optionalClientScopes": ["srof:read"]
}
json.dump(payload,open(path,"w",encoding="utf-8"),indent=2)
PY

CLIENT_UUID="$("${KC[@]}" get clients -r "$REALM" -q "clientId=$CLIENT_ID" --fields id,clientId --format csv --noquotes 2>/dev/null | awk -F, -v c="$CLIENT_ID" '$2==c{print $1; exit}')"
if [ -z "$CLIENT_UUID" ]; then
  "${KC[@]}" create clients -r "$REALM" -f "$TMP" >/dev/null
  CLIENT_UUID="$("${KC[@]}" get clients -r "$REALM" -q "clientId=$CLIENT_ID" --fields id,clientId --format csv --noquotes | awk -F, -v c="$CLIENT_ID" '$2==c{print $1; exit}')"
  echo "OPENAI_SROF_CLIENT_CREATED=YES"
else
  "${KC[@]}" update "clients/$CLIENT_UUID" -r "$REALM" -f "$TMP" >/dev/null
  echo "OPENAI_SROF_CLIENT_CREATED=NO_UPDATED"
fi

test -n "$CLIENT_UUID"

READBACK="$(mktemp)"
trap 'rm -f "$TMP" "$READBACK"' EXIT
"${KC[@]}" get "clients/$CLIENT_UUID" -r "$REALM" > "$READBACK"

python3 - "$READBACK" "$CLIENT_ID" "$REDIRECT_URI" <<'PY'
import json,sys
path,client_id,redirect_uri=sys.argv[1:]
d=json.load(open(path,encoding="utf-8"))
assert d.get("clientId")==client_id
assert d.get("enabled") is True
assert d.get("publicClient") is True
assert d.get("standardFlowEnabled") is True
assert d.get("implicitFlowEnabled") is False
assert d.get("directAccessGrantsEnabled") is False
assert d.get("serviceAccountsEnabled") is False
assert d.get("fullScopeAllowed") is False
assert redirect_uri in (d.get("redirectUris") or [])
assert (d.get("attributes") or {}).get("pkce.code.challenge.method")=="S256"
assert "srof:read" in (d.get("optionalClientScopes") or [])
print("OPENAI_SROF_CLIENT_READBACK=PASS")
print("OPENAI_SROF_CLIENT_PKCE_S256=PASS")
print("OPENAI_SROF_CLIENT_SCOPE=PASS")
print("OPENAI_SROF_CLIENT_LOOPBACK_ONLY=PASS")
PY

unset KC_BOOTSTRAP_ADMIN_PASSWORD KC_DB_PASSWORD
echo "CLIENT_ID=$CLIENT_ID"
echo "REDIRECT_URI=$REDIRECT_URI"
echo "DCP_USED=NO"
echo "GITHUB_ACTIONS_TRANSPORT=NO"
