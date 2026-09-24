#!/usr/bin/env bash
set -Eeuo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
APP_DIR="/opt/scientiam/remote-ops-gateway"
OAUTH_SRC="$REPO_ROOT/deploy/native-auth/srof-oauth.env.example"
OAUTH_DST="/etc/scientiam/remote-ops/srof-oauth.env"
CF_ENV="/etc/scientiam/remote-ops/cloudflare-access.env"
SERVICE="scientiam-remote-ops-gateway.service"
TMP_VENV="$(mktemp -d /tmp/srof-auth-test.XXXXXX)"
ENV_INSTALLED=0

cleanup() { rm -rf "$TMP_VENV"; }
rollback() {
  rc=$?
  if [ "$rc" -ne 0 ]; then
    echo "ACTIVATION_FAILED_RC=$rc" >&2
    if [ "$ENV_INSTALLED" -eq 1 ] && [ -f "$OAUTH_DST" ]; then
      mv "$OAUTH_DST" "$OAUTH_DST.failed.$(date +%Y%m%dT%H%M%S)" || true
      echo "OAUTH_ENV_ROLLED_BACK=YES" >&2
    fi
    systemctl daemon-reload || true
    systemctl restart "$SERVICE" || true
    echo "SROF_SERVICE_RECOVERY_ATTEMPTED=YES" >&2
  fi
  cleanup
  exit "$rc"
}
trap rollback ERR
trap cleanup EXIT

if [ "$(id -u)" -ne 0 ]; then
  echo "BLOCKED: run with sudo/root" >&2
  exit 3
fi

echo "=== STRAN/SROF · ACTIVATE NATIVE OAUTH ==="
echo "HOST=$(hostname -s)"
echo "TIME=$(date -Is)"
test "$(hostname -s)" = "profesys-scientiam"

if [ -r "$CF_ENV" ] && grep -Eq '^SROF_CF_ACCESS_REQUIRED=(1|true|yes|on)$' "$CF_ENV"; then
  echo "BLOCKED: Cloudflare Access enforcement is enabled; native OAuth requires it disabled" >&2
  exit 10
fi

curl -fsS http://127.0.0.1:9006/health/ready >/dev/null
echo "KEYCLOAK_READY=PASS"

DISCOVERY="$(mktemp)"
curl -fsS http://127.0.0.1:8096/realms/scientiam-srof/.well-known/openid-configuration > "$DISCOVERY"
python3 - "$DISCOVERY" <<'PY'
import json,sys
d=json.load(open(sys.argv[1],encoding="utf-8"))
assert d.get("issuer")=="https://auth.scientiam.com.ar/realms/scientiam-srof", d.get("issuer")
assert "S256" in d.get("code_challenge_methods_supported",[]), "PKCE S256 missing"
assert bool(d.get("client_id_metadata_document_supported")), "CIMD discovery flag missing"
print("KEYCLOAK_ISSUER=PASS")
print("KEYCLOAK_PKCE_S256=PASS")
print("KEYCLOAK_CIMD=PASS")
PY
rm -f "$DISCOVERY"

"$REPO_ROOT/deploy/native-auth/verify-keycloak-policy.sh"

echo "=== PRE-DEPLOY TEST VENV ==="
python3 -m venv "$TMP_VENV/venv"
"$TMP_VENV/venv/bin/pip" -q install --upgrade pip
"$TMP_VENV/venv/bin/pip" -q install -e "$REPO_ROOT/gateway[dev]"
"$TMP_VENV/venv/bin/pytest" -q "$REPO_ROOT/gateway/tests"
echo "GATEWAY_TESTS=PASS"

install -d -m 0750 -o root -g scientiam-remoteops /etc/scientiam/remote-ops
install -m 0640 -o root -g scientiam-remoteops "$OAUTH_SRC" "$OAUTH_DST"
ENV_INSTALLED=1
echo "OAUTH_ENV_INSTALLED=PASS"

echo "=== UPGRADE MANAGED GATEWAY ==="
systemctl stop "$SERVICE"
"$REPO_ROOT/deploy/remote-ops/prepare-gateway-server.sh" prepare
systemctl start "$SERVICE"

for _ in $(seq 1 30); do
  if systemctl is-active --quiet "$SERVICE" && ss -ltn | grep -Fq "127.0.0.1:8765"; then
    break
  fi
  sleep 1
done
systemctl is-active --quiet "$SERVICE"
ss -ltn | grep -Fq "127.0.0.1:8765"
if ss -ltn | grep -Eq "0\.0\.0\.0:8765|\[::\]:8765"; then
  echo "SROF_EXTERNAL_BIND=FAIL" >&2
  exit 20
fi
echo "SROF_OAUTH_SERVICE=PASS"
echo "SROF_LOOPBACK_ONLY=PASS"

HEADERS="$(mktemp)"
BODY="$(mktemp)"
HTTP_CODE="$(curl -sS -D "$HEADERS" -o "$BODY" -w "%{http_code}" http://127.0.0.1:8765/mcp)"
if [ "$HTTP_CODE" != "401" ]; then
  echo "ANONYMOUS_MCP_DENY=FAIL HTTP_CODE=$HTTP_CODE" >&2
  cat "$BODY" >&2 || true
  rm -f "$HEADERS" "$BODY"
  exit 21
fi
grep -qi "^www-authenticate: Bearer" "$HEADERS"
grep -q "resource_metadata=" "$HEADERS"
echo "ANONYMOUS_MCP_DENY=PASS"
rm -f "$HEADERS" "$BODY"

META="$(mktemp)"
curl -fsS http://127.0.0.1:8765/.well-known/oauth-protected-resource/mcp > "$META"
python3 - "$META" <<'PY'
import json,sys
d=json.load(open(sys.argv[1],encoding="utf-8"))
assert str(d.get("resource","")).rstrip("/")=="https://srof.scientiam.com.ar/mcp"
servers=[str(x).rstrip("/") for x in d.get("authorization_servers",[])]
assert "https://auth.scientiam.com.ar/realms/scientiam-srof" in servers
assert "srof:read" in (d.get("scopes_supported") or [])
assert "header" in (d.get("bearer_methods_supported") or [])
print("PROTECTED_RESOURCE_METADATA=PASS")
print("OAUTH_RESOURCE_BINDING=PASS")
print("OAUTH_SCOPE_ADVERTISEMENT=PASS")
PY
rm -f "$META"

ENV_INSTALLED=0
echo "SROF_NATIVE_OAUTH_LOCAL=PASS"
echo "PUBLIC_ROUTES_CREATED=NO"
echo "DCP_USED=NO"
echo "GITHUB_ACTIONS_TRANSPORT=NO"
