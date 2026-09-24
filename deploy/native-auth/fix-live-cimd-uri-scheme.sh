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

echo "=== STRAN/SROF · FIX LIVE CIMD URI-SCHEME POLICY ==="
echo "HOST=$(hostname -s)"
echo "TIME=$(date -Is)"

test -r "$ENV_FILE"
set -a
# shellcheck disable=SC1090
. "$ENV_FILE"
set +a

KC=(docker compose --env-file "$ENV_FILE" -f "$COMPOSE" exec -T keycloak /opt/keycloak/bin/kcadm.sh)
"${KC[@]}" config credentials   --server http://localhost:8080   --realm master   --user "$KC_BOOTSTRAP_ADMIN_USERNAME"   --password "$KC_BOOTSTRAP_ADMIN_PASSWORD" >/dev/null

BEFORE="$(mktemp)"
AFTER="$(mktemp)"
trap 'rm -f "$BEFORE" "$AFTER"' EXIT

"${KC[@]}" get client-policies/policies -r "$REALM" > "$BEFORE"

python3 - "$BEFORE" "$AFTER" <<'PY'
import json,sys
src,dst=sys.argv[1:]
doc=json.load(open(src,encoding="utf-8"))
changed=0
for policy in doc.get("policies",[]):
    if policy.get("name")!="chatgpt-cimd-policy":
        continue
    for cond in policy.get("conditions",[]):
        if cond.get("condition")!="client-id-uri":
            continue
        cfg=cond.setdefault("configuration",{})
        value=cfg.get("client-id-uri-scheme")
        if value=="https":
            cfg["client-id-uri-scheme"]=["https"]
            changed+=1
        elif value==["https"]:
            pass
        else:
            raise SystemExit(f"BLOCKED unexpected client-id-uri-scheme={value!r}")
if changed==0:
    print("LIVE_POLICY_CHANGE=NOT_NEEDED_ALREADY_CORRECT")
else:
    print("LIVE_POLICY_CHANGE=PREPARED")
with open(dst,"w",encoding="utf-8") as f:
    json.dump(doc,f,indent=2)
    f.write("\n")
PY

cat "$AFTER" | "${KC[@]}" update client-policies/policies -r "$REALM" -f - >/dev/null
echo "LIVE_POLICY_UPDATE=PASS"

bash "$REPO_ROOT/deploy/native-auth/verify-keycloak-policy.sh"

echo
echo "=== AUTHORIZATION ENDPOINT SMOKE ==="
CODE="$(curl -sS -o /tmp/srof-auth-smoke.body -w '%{http_code}'   'https://auth.scientiam.com.ar/realms/scientiam-srof/protocol/openid-connect/auth?client_id=account-console&redirect_uri=https%3A%2F%2Fauth.scientiam.com.ar%2Frealms%2Fscientiam-srof%2Faccount%2F&response_type=code&scope=openid&code_challenge=AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA&code_challenge_method=S256')"
rm -f /tmp/srof-auth-smoke.body

echo "AUTHORIZATION_ENDPOINT_HTTP=$CODE"
if [ "$CODE" = "500" ]; then
  echo "AUTHORIZATION_ENDPOINT=FAIL" >&2
  exit 20
fi
echo "AUTHORIZATION_ENDPOINT=PASS"
echo "KEYCLOAK_RESTART_REQUIRED=NO"
echo "SECRETS_PRINTED=NO"
