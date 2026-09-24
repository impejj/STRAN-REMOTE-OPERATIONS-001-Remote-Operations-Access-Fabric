#!/usr/bin/env bash
set -euo pipefail

SERVICE="cloudflared.service"

echo "=== STRAN/SROF · CLOUDFLARE REMOTE-MANAGED METADATA ==="
echo "HOST=$(hostname -s)"
echo "TIME=$(date -Is)"

command -v systemctl >/dev/null
command -v journalctl >/dev/null
command -v grep >/dev/null
command -v python3 >/dev/null

systemctl is-active --quiet "$SERVICE"
echo "CLOUDFLARED_SERVICE=PASS"

EXEC_RAW="$(systemctl show "$SERVICE" -p ExecStart --value 2>/dev/null || true)"
if grep -Eq -- '(^|[[:space:]])--token-file([=[:space:]])' <<<"$EXEC_RAW"; then
  echo "CLOUDFLARED_MANAGEMENT_MODE=REMOTE_MANAGED_TOKEN_FILE"
elif grep -Eq -- '(^|[[:space:]])--token([=[:space:]])' <<<"$EXEC_RAW"; then
  echo "CLOUDFLARED_MANAGEMENT_MODE=REMOTE_MANAGED_TOKEN"
else
  echo "CLOUDFLARED_MANAGEMENT_MODE=NOT_REMOTE_MANAGED_BY_TOKEN"
  exit 20
fi

echo
echo "=== TOKEN FILE METADATA ONLY ==="
TOKEN_PATH="$(sed -nE 's/.*--token-file[= ]+([^ ;}]+).*/\1/p' <<<"$EXEC_RAW" | head -1)"
if [ -n "$TOKEN_PATH" ] && [ -f "$TOKEN_PATH" ]; then
  echo "TOKEN_FILE_PRESENT=YES"
  stat -c 'TOKEN_FILE_MODE=%a TOKEN_FILE_OWNER=%U TOKEN_FILE_GROUP=%G TOKEN_FILE_BYTES=%s' "$TOKEN_PATH"
  echo "TOKEN_CONTENT_READ=NO"
else
  echo "TOKEN_FILE_PRESENT=NO_OR_UNRESOLVED"
fi

echo
echo "=== JOURNAL-DERIVED NON-SECRET METADATA ==="
TMP="$(mktemp)"
trap 'rm -f "$TMP"' EXIT
journalctl -u "$SERVICE" --no-pager -n 1200 -o cat >"$TMP" 2>/dev/null || true

TUNNEL_IDS="$(grep -Eo 'tunnelID=[0-9a-fA-F-]{36}' "$TMP" | sed 's/^tunnelID=//' | awk '!seen[$0]++' || true)"
if [ -n "$TUNNEL_IDS" ]; then
  while IFS= read -r id; do
    [ -n "$id" ] && echo "TUNNEL_ID=$id"
  done <<<"$TUNNEL_IDS"
else
  echo "TUNNEL_ID=NOT_FOUND_IN_RECENT_JOURNAL"
fi

CONNECTION_IDS="$(grep -Eo 'connIndex=[0-9]+' "$TMP" | sed 's/^connIndex=//' | sort -n | uniq || true)"
if [ -n "$CONNECTION_IDS" ]; then
  echo "OBSERVED_CONNECTION_INDEXES=$(paste -sd, <<<"$CONNECTION_IDS")"
fi

# cloudflared remotely-managed startup/update logs often include the remotely
# supplied ingress config. Extract only hostname/service pairs from JSON-ish
# or text representations; never print raw journal lines.
python3 - "$TMP" <<'PY'
import re,sys
text=open(sys.argv[1],encoding="utf-8",errors="replace").read()
hosts=[]
services=[]
for pat in (
    r'"hostname"\s*:\s*"([^"]+)"',
    r'hostname[=:]\s*([^\s,}\]"]+)',
):
    hosts.extend(re.findall(pat,text,re.I))
for pat in (
    r'"service"\s*:\s*"([^"]+)"',
    r'service[=:]\s*([^\s,}\]"]+)',
):
    services.extend(re.findall(pat,text,re.I))

def clean(xs):
    out=[]
    for x in xs:
        x=x.strip()
        if not x or len(x)>300: continue
        if x not in out: out.append(x)
    return out

hosts=clean(hosts)
services=clean(services)
if hosts:
    for h in hosts[-10:]:
        print("REMOTE_CONFIG_HOSTNAME="+h)
else:
    print("REMOTE_CONFIG_HOSTNAME=NOT_FOUND_IN_RECENT_JOURNAL")
if services:
    for s in services[-10:]:
        print("REMOTE_CONFIG_SERVICE="+s)
else:
    print("REMOTE_CONFIG_SERVICE=NOT_FOUND_IN_RECENT_JOURNAL")
PY

echo
echo "=== RECENT CONNECTION HEALTH COUNTS ==="
EST="$(grep -Ec 'Registered tunnel connection|Connection registered|connected to edge' "$TMP" || true)"
ERR="$(grep -Eci 'ERR|error|failed|connection.*closed' "$TMP" || true)"
echo "RECENT_CONNECTION_SUCCESS_HINTS=$EST"
echo "RECENT_ERROR_HINTS=$ERR"

echo
echo "CLOUDFLARE_REMOTE_METADATA=COMPLETE"
echo "TOKEN_CONTENT_READ=NO"
echo "NO_CONFIGURATION_CHANGED=YES"
echo "DCP_USED=NO"
echo "GITHUB_ACTIONS_TRANSPORT=NO"
