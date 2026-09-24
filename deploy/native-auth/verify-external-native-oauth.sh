#!/usr/bin/env bash
set -euo pipefail

AUTH_HOST="${SROF_AUTH_HOSTNAME:-auth.scientiam.com.ar}"
MCP_HOST="${SROF_PUBLIC_HOSTNAME:-srof.scientiam.com.ar}"
ISSUER="https://${AUTH_HOST}/realms/scientiam-srof"
RESOURCE="https://${MCP_HOST}/mcp"

echo "=== STRAN/SROF · EXTERNAL NATIVE OAUTH READBACK ==="
echo "HOST=$(hostname -s)"
echo "TIME=$(date -Is)"
echo "AUTH_HOST=$AUTH_HOST"
echo "MCP_HOST=$MCP_HOST"

echo
echo "=== DNS/TLS + OIDC DISCOVERY ==="
AUTH_DISC="$(mktemp)"
MCP_META="$(mktemp)"
HEADERS="$(mktemp)"
BODY="$(mktemp)"
trap 'rm -f "$AUTH_DISC" "$MCP_META" "$HEADERS" "$BODY"' EXIT

curl -fsS --max-time 15 "https://${AUTH_HOST}/realms/scientiam-srof/.well-known/openid-configuration" > "$AUTH_DISC"
python3 - "$AUTH_DISC" "$ISSUER" <<'PY'
import json,sys
path,issuer=sys.argv[1:]
d=json.load(open(path,encoding="utf-8"))
assert d.get("issuer")==issuer, (d.get("issuer"),issuer)
assert "S256" in d.get("code_challenge_methods_supported",[])
assert bool(d.get("client_id_metadata_document_supported"))
print("EXTERNAL_AUTH_DISCOVERY=PASS")
print("EXTERNAL_PKCE_S256=PASS")
print("EXTERNAL_CIMD=PASS")
PY

echo
echo "=== EXTERNAL MCP ANONYMOUS DENY ==="
HTTP_CODE="$(curl -sS --max-time 15 -D "$HEADERS" -o "$BODY" -w "%{http_code}" "https://${MCP_HOST}/mcp")"
echo "ANONYMOUS_HTTP_CODE=$HTTP_CODE"
if [ "$HTTP_CODE" != "401" ]; then
  echo "EXTERNAL_ANONYMOUS_MCP_DENY=FAIL" >&2
  head -c 1000 "$BODY" >&2 || true
  echo >&2
  exit 20
fi
grep -qi "^www-authenticate: Bearer" "$HEADERS"
grep -q "resource_metadata=" "$HEADERS"
echo "EXTERNAL_ANONYMOUS_MCP_DENY=PASS"

echo
echo "=== EXTERNAL RFC9728 METADATA ==="
curl -fsS --max-time 15 "https://${MCP_HOST}/.well-known/oauth-protected-resource/mcp" > "$MCP_META"
python3 - "$MCP_META" "$RESOURCE" "$ISSUER" <<'PY'
import json,sys
path,resource,issuer=sys.argv[1:]
d=json.load(open(path,encoding="utf-8"))
assert str(d.get("resource","")).rstrip("/")==resource.rstrip("/")
servers=[str(x).rstrip("/") for x in d.get("authorization_servers",[])]
assert issuer.rstrip("/") in servers
assert "srof:read" in (d.get("scopes_supported") or [])
assert "header" in (d.get("bearer_methods_supported") or [])
print("EXTERNAL_PROTECTED_RESOURCE_METADATA=PASS")
print("EXTERNAL_RESOURCE_BINDING=PASS")
print("EXTERNAL_SCOPE_ADVERTISEMENT=PASS")
PY

echo
echo "SROF_EXTERNAL_NATIVE_OAUTH_TRANSPORT=PASS"
echo "DCP_USED=NO"
echo "GITHUB_ACTIONS_TRANSPORT=NO"
