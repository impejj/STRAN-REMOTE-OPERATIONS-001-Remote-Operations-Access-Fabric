#!/usr/bin/env bash
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
COMPOSE="$REPO_ROOT/deploy/native-auth/compose.yml"
ENV_FILE="/etc/scientiam/remote-ops/keycloak.env"
REALM="scientiam-srof"
EXPECTED_AUD="https://srof.scientiam.com.ar/mcp"

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
"${KC[@]}" config credentials --server http://localhost:8080 --realm master --user "$KC_BOOTSTRAP_ADMIN_USERNAME" --password "$KC_BOOTSTRAP_ADMIN_PASSWORD" >/dev/null

SCOPES="$(mktemp)"
DEFAULTS="$(mktemp)"
PROFILES="$(mktemp)"
POLICIES="$(mktemp)"
trap 'rm -f "$SCOPES" "$DEFAULTS" "$PROFILES" "$POLICIES"' EXIT

"${KC[@]}" get client-scopes -r "$REALM" > "$SCOPES"
"${KC[@]}" get default-optional-client-scopes -r "$REALM" > "$DEFAULTS"
"${KC[@]}" get client-policies/profiles -r "$REALM" > "$PROFILES"
"${KC[@]}" get client-policies/policies -r "$REALM" > "$POLICIES"

python3 - "$SCOPES" "$DEFAULTS" "$PROFILES" "$POLICIES" "$EXPECTED_AUD" <<'PY'
import json,sys
scopes_path,defaults_path,profiles_path,policies_path,expected_aud=sys.argv[1:]
scopes=json.load(open(scopes_path,encoding="utf-8"))
defaults=json.load(open(defaults_path,encoding="utf-8"))
profiles=json.load(open(profiles_path,encoding="utf-8"))
policies=json.load(open(policies_path,encoding="utf-8"))

scope=next((x for x in scopes if x.get("name")=="srof:read"),None)
assert scope is not None, "missing srof:read client scope"
mappers=scope.get("protocolMappers") or []
aud=next((m for m in mappers if m.get("protocolMapper")=="oidc-audience-mapper"),None)
assert aud is not None, "missing audience mapper"
assert (aud.get("config") or {}).get("included.custom.audience")==expected_aud, "wrong audience"
print("SROF_READ_SCOPE=PASS")
print("SROF_AUDIENCE_BINDING=PASS")

assert any(x.get("name")=="srof:read" for x in defaults), "srof:read is not realm-default optional"
print("SROF_SCOPE_DEFAULT_OPTIONAL=PASS")

plist=profiles.get("profiles") or []
profile=next((x for x in plist if x.get("name")=="chatgpt-cimd-profile"),None)
assert profile is not None, "missing chatgpt CIMD profile"
exec_=next((x for x in (profile.get("executors") or []) if x.get("executor")=="client-id-metadata-document"),None)
assert exec_ is not None, "missing client-id-metadata-document executor"
cfg=exec_.get("configuration") or {}
trusted=set(cfg.get("cimd-allow-permitted-domains") or [])
assert "chatgpt.com" in trusted and "persistent.oaistatic.com" in trusted, "trusted metadata domains incomplete"
assert cfg.get("cimd-allow-http-scheme") in (False,"false"), "HTTP CIMD must be disabled"
assert cfg.get("only-allow-confidential-client") in (True,"true"), "ChatGPT profile must require confidential client"
print("CHATGPT_CIMD_PROFILE=PASS")

polist=policies.get("policies") or []
policy=next((x for x in polist if x.get("name")=="chatgpt-cimd-policy"),None)
assert policy is not None and policy.get("enabled") is True, "missing/enabled CIMD policy"
cond=next((x for x in (policy.get("conditions") or []) if x.get("condition")=="client-id-uri"),None)
assert cond is not None, "missing client-id-uri condition"
ccfg=cond.get("configuration") or {}
domains=set(ccfg.get("client-id-uri-allow-permitted-domains") or [])
assert "chatgpt.com" in domains, "CIMD policy not restricted to chatgpt.com"
assert "chatgpt-cimd-profile" in (policy.get("profiles") or []), "profile not associated"
print("CHATGPT_CIMD_POLICY=PASS")
PY

echo "KEYCLOAK_POLICY_READBACK=PASS"
echo "SECRETS_PRINTED=NO"
