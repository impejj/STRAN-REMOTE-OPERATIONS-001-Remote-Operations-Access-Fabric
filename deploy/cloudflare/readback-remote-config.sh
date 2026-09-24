#!/usr/bin/env bash
set -euo pipefail

SERVICE="cloudflared.service"

echo "=== STRAN/SROF · CLOUDFLARE REMOTE CONFIG READBACK ==="
echo "HOST=$(hostname -s)"
echo "TIME=$(date -Is)"

command -v journalctl >/dev/null
command -v python3 >/dev/null
systemctl is-active --quiet "$SERVICE"
echo "CLOUDFLARED_SERVICE=PASS"

TMP="$(mktemp)"
trap 'rm -f "$TMP"' EXIT

# Read a generous recent window. This does not read the tunnel token or any
# credential file; only cloudflared service logs are inspected.
journalctl -u "$SERVICE" --no-pager -n 10000 -o cat >"$TMP" 2>/dev/null || true

python3 - "$TMP" <<'PY'
from __future__ import annotations
import json,re,sys

path=sys.argv[1]
lines=open(path,encoding="utf-8",errors="replace").read().splitlines()

update=None
for line in reversed(lines):
    if "Updated to new configuration" in line:
        update=line
        break

if update is None:
    print("REMOTE_CONFIG_EVENT=NOT_FOUND")
    raise SystemExit(20)

# zerolog renders the string-valued config field as a quoted/escaped JSON
# string, followed by version=<n>. Extract only those two structured fields.
m=re.search(
    r'config=(?P<config>"(?:\\.|[^"])*"|null)\s+version=(?P<version>\d+)',
    update,
)
if not m:
    print("REMOTE_CONFIG_EVENT=FOUND_BUT_PARSE_FAILED")
    raise SystemExit(21)

raw=m.group("config")
version=int(m.group("version"))
print("REMOTE_CONFIG_EVENT=PASS")
print(f"REMOTE_CONFIG_VERSION={version}")

if raw=="null":
    print("REMOTE_CONFIG_NULL=YES")
    print("REMOTE_CONFIG_INGRESS_COUNT=0")
    raise SystemExit(0)

try:
    # First decode the quoted zerolog field, then decode the JSON config.
    encoded=json.loads(raw)
    cfg=json.loads(encoded)
except Exception as exc:
    print("REMOTE_CONFIG_DECODE=FAIL")
    print("REMOTE_CONFIG_DECODE_ERROR="+type(exc).__name__)
    raise SystemExit(22)

print("REMOTE_CONFIG_DECODE=PASS")
ingress=cfg.get("ingress") or []
print(f"REMOTE_CONFIG_INGRESS_COUNT={len(ingress)}")

for idx,rule in enumerate(ingress):
    if not isinstance(rule,dict):
        continue
    hostname=rule.get("hostname")
    service=rule.get("service")
    if hostname:
        print(f"INGRESS_{idx}_HOSTNAME={hostname}")
    else:
        print(f"INGRESS_{idx}_HOSTNAME=<catch_all>")
    if service:
        print(f"INGRESS_{idx}_SERVICE={service}")
    origin=rule.get("originRequest")
    if isinstance(origin,dict):
        # Print only non-secret origin behaviour relevant to SROF design.
        for key in ("connectTimeout","httpHostHeader","noTLSVerify"):
            if key in origin:
                print(f"INGRESS_{idx}_ORIGIN_{key}={origin[key]}")

warp=cfg.get("warp-routing") or cfg.get("warpRouting")
if isinstance(warp,dict):
    print("WARP_ROUTING_ENABLED="+str(bool(warp.get("enabled"))).lower())

# Parse exact registered-connection lines only. These fields are operational
# metadata, not secrets.
connections={}
for line in lines:
    if "Registered tunnel connection" not in line and "Connection registered" not in line:
        continue
    mi=re.search(r'connIndex=(\d+)',line)
    if not mi:
        continue
    idx=int(mi.group(1))
    loc=re.search(r'location=([A-Z0-9-]+)',line)
    proto=re.search(r'protocol=([A-Za-z0-9-]+)',line)
    connections[idx]={
        "location": loc.group(1) if loc else "",
        "protocol": proto.group(1) if proto else "",
    }

for idx in sorted(connections):
    meta=connections[idx]
    print(f"CONNECTION_{idx}_LOCATION={meta['location'] or 'UNKNOWN'}")
    print(f"CONNECTION_{idx}_PROTOCOL={meta['protocol'] or 'UNKNOWN'}")

# Count only actual zerolog error-level lines, not arbitrary occurrences of
# the word 'error' inside informational payloads.
exact_err=sum(1 for line in lines if re.search(r'(^|\s)ERR(\s|$)',line))
exact_warn=sum(1 for line in lines if re.search(r'(^|\s)WRN(\s|$)',line))
print(f"EXACT_ERR_LINES_IN_WINDOW={exact_err}")
print(f"EXACT_WRN_LINES_IN_WINDOW={exact_warn}")
PY

echo
echo "CLOUDFLARE_REMOTE_CONFIG_READBACK=COMPLETE"
echo "TOKEN_CONTENT_READ=NO"
echo "NO_CONFIGURATION_CHANGED=YES"
echo "DCP_USED=NO"
echo "GITHUB_ACTIONS_TRANSPORT=NO"
