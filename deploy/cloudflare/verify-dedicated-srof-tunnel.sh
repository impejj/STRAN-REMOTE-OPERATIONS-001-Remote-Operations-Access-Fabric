#!/usr/bin/env bash
set -euo pipefail

SERVICE="cloudflared-scientiam-srof.service"
EXPECTED_HOSTNAME="${SROF_PUBLIC_HOSTNAME:-srof.scientiam.com.ar}"
EXPECTED_ORIGIN="http://127.0.0.1:8765"
EXPECTED_AUTH_HOSTNAME="${SROF_AUTH_HOSTNAME:-auth.scientiam.com.ar}"
EXPECTED_AUTH_ORIGIN="http://127.0.0.1:8097"

echo "=== STRAN/SROF · VERIFY DEDICATED CLOUDFLARE TUNNEL ==="
echo "HOST=$(hostname -s)"
echo "TIME=$(date -Is)"
echo "EXPECTED_HOSTNAME=$EXPECTED_HOSTNAME"
echo "EXPECTED_ORIGIN=$EXPECTED_ORIGIN"
echo "EXPECTED_AUTH_HOSTNAME=$EXPECTED_AUTH_HOSTNAME"
echo "EXPECTED_AUTH_ORIGIN=$EXPECTED_AUTH_ORIGIN"

systemctl is-active --quiet "$SERVICE"
echo "DEDICATED_TUNNEL_SERVICE=PASS"

TMP="$(mktemp)"
trap 'rm -f "$TMP"' EXIT
journalctl -u "$SERVICE" --no-pager -n 5000 -o cat > "$TMP" 2>/dev/null || true

python3 - "$TMP" "$EXPECTED_HOSTNAME" "$EXPECTED_ORIGIN" "$EXPECTED_AUTH_HOSTNAME" "$EXPECTED_AUTH_ORIGIN" <<'PY'
import json,re,sys
path,expected_host,expected_origin,expected_auth_host,expected_auth_origin=sys.argv[1:]
lines=open(path,encoding="utf-8",errors="replace").read().splitlines()
update=None
for line in reversed(lines):
    if "Updated to new configuration" in line:
        update=line
        break
if update is None:
    print("REMOTE_CONFIG_EVENT=NOT_FOUND")
    raise SystemExit(20)
m=re.search(r'config=(?P<config>"(?:\\.|[^"])*"|null)\\s+version=(?P<version>\\d+)',update)
if not m:
    print("REMOTE_CONFIG_PARSE=FAIL")
    raise SystemExit(21)
if m.group("config")=="null":
    print("REMOTE_CONFIG_NULL=YES")
    raise SystemExit(22)
cfg=json.loads(json.loads(m.group("config")))
ingress=cfg.get("ingress") or []
print("REMOTE_CONFIG_VERSION="+m.group("version"))
print("REMOTE_CONFIG_INGRESS_COUNT="+str(len(ingress)))
pairs=[]
for i,rule in enumerate(ingress):
    if not isinstance(rule,dict): continue
    h=rule.get("hostname") or "<catch_all>"
    s=rule.get("service") or ""
    print(f"INGRESS_{i}_HOSTNAME={h}")
    print(f"INGRESS_{i}_SERVICE={s}")
    pairs.append((h,s))
if (expected_host,expected_origin) not in pairs:
    print("SROF_INGRESS_MATCH=FAIL")
    raise SystemExit(23)
print("SROF_INGRESS_MATCH=PASS")
if (expected_auth_host,expected_auth_origin) not in pairs:
    print("AUTH_INGRESS_MATCH=FAIL")
    raise SystemExit(25)
print("AUTH_INGRESS_MATCH=PASS")
for h,s in pairs:
    if h=="<catch_all>" and s!="http_status:404":
        print("CATCH_ALL_POLICY=FAIL")
        raise SystemExit(24)
print("CATCH_ALL_POLICY=PASS")
PY

echo "DEDICATED_CLOUDFLARE_TUNNEL=PASS"
echo "SROF_AND_AUTH_INGRESS=PASS"
echo "DCP_USED=NO"
echo "GITHUB_ACTIONS_TRANSPORT=NO"
