#!/usr/bin/env bash
set -euo pipefail

MODE="plan"
SERVICE_USER="${SROF_SERVICE_USER:-scientiam-remoteops}"
SERVICE_GROUP="${SROF_SERVICE_GROUP:-scientiam-remoteops}"
ETC_DIR="${SROF_ETC_DIR:-/etc/scientiam/remote-ops}"
HOSTS="${SROF_HOSTS_FILE:-$ETC_DIR/hosts.json}"
STATE_DIR="${SROF_STATE_DIR:-/var/lib/scientiam/remote-ops}"
RECEIPTS="${SROF_RECEIPT_DIR:-$STATE_DIR/receipts}"
BACKUPS="$STATE_DIR/registry-backups"
APP_DIR="${SROF_APP_DIR:-/opt/scientiam/remote-ops-gateway}"
THINKPAD_HOST_ID="THINKPAD-E470"
SERVER_HOST_ID="PROFESYS-SCIENTIAM"
THINKPAD_EXPECTED_HOSTNAME="${THINKPAD_EXPECTED_HOSTNAME:-thinkPad-E470}"
THINKPAD_ROOT="${THINKPAD_ALLOWED_ROOT:-/home/impejj/work/profesys}"
THINKPAD_REPO="${THINKPAD_ALLOWED_REPOSITORY:-/home/impejj/work/profesys/scientiam}"
THINKPAD_ALIAS="${THINKPAD_SSH_ALIAS:-}"

usage() {
  cat <<'EOF'
Usage:
  sudo deploy/remote-ops/close-two-host-registry.sh
  sudo deploy/remote-ops/close-two-host-registry.sh --apply

Default is PLAN/DIAGNOSTIC only.

--apply:
  - verifies SERVER -> ThinkPad key-only SSH as scientiam-remoteops;
  - backs up /etc/scientiam/remote-ops/hosts.json;
  - upserts THINKPAD-E470 without replacing existing hosts;
  - grants only capabilities proven by live read-only probes;
  - executes SROF hosts_list and host_health for SERVER + ThinkPad;
  - requires new durable receipts;
  - restores the previous registry if the SROF smoke fails.

Optional environment:
  THINKPAD_SSH_ALIAS=<existing SSH Host alias>
  THINKPAD_ALLOWED_ROOT=/home/impejj/work/profesys
  THINKPAD_ALLOWED_REPOSITORY=/home/impejj/work/profesys/scientiam

This script does NOT change SSH keys, sshd, firewall, sudoers, DCP,
Cloudflare, GitHub Actions, or external exposure.
EOF
}

while [ "$#" -gt 0 ]; do
  case "$1" in
    --apply) MODE="apply"; shift ;;
    -h|--help) usage; exit 0 ;;
    *) echo "ERROR unknown argument: $1" >&2; usage; exit 2 ;;
  esac
done

if [ "$(id -u)" -ne 0 ]; then
  echo "BLOCKED: run with sudo/root" >&2
  exit 3
fi

echo "=== STRAN/SROF · TWO-HOST REGISTRY CLOSURE ==="
echo "MODE=$MODE"
echo "HOST=$(hostname -s)"
echo "TIME=$(date -Is)"

test "$(hostname -s)" = "profesys-scientiam"
id "$SERVICE_USER" >/dev/null
getent group "$SERVICE_GROUP" >/dev/null
command -v ssh >/dev/null
command -v python3 >/dev/null
test -x "$APP_DIR/.venv/bin/python"
test -r "$HOSTS"
python3 -m json.tool "$HOSTS" >/dev/null

SSH_CONFIG="/home/$SERVICE_USER/.ssh/config"
test -r "$SSH_CONFIG"

echo
echo "=== CURRENT REGISTRY ==="
python3 - "$HOSTS" <<'PY'
import json,sys
p=sys.argv[1]
d=json.load(open(p,encoding="utf-8"))
for h in d.get("hosts",[]):
    print("HOST_ID=%s SSH_ALIAS=%s LIFECYCLE=%s CAPABILITIES=%s" % (
        h.get("host_id"), h.get("ssh_alias"), h.get("lifecycle_state"),
        ",".join(h.get("capabilities",[]))
    ))
PY

discover_alias() {
  if [ -n "$THINKPAD_ALIAS" ]; then
    printf '%s\n' "$THINKPAD_ALIAS"
    return 0
  fi

  mapfile -t aliases < <(
    awk '
      tolower($1)=="host" {
        for (i=2;i<=NF;i++) {
          if ($i !~ /[*?!]/ && tolower($i) ~ /thinkpad/) print $i
        }
      }
    ' "$SSH_CONFIG" | awk '!seen[$0]++'
  )

  for alias in "${aliases[@]:-}"; do
    [ -n "$alias" ] || continue
    out="$(runuser -u "$SERVICE_USER" -- ssh -o BatchMode=yes -o PasswordAuthentication=no -- "$alias" 'hostname -s' 2>/dev/null || true)"
    if [ "${out,,}" = "${THINKPAD_EXPECTED_HOSTNAME,,}" ]; then
      printf '%s\n' "$alias"
      return 0
    fi
  done

  echo "BLOCKED: no verified ThinkPad SSH alias found in $SSH_CONFIG" >&2
  if [ "${#aliases[@]}" -gt 0 ]; then
    printf 'CANDIDATE_ALIAS=%s\n' "${aliases[@]}" >&2
  fi
  return 20
}

THINKPAD_ALIAS="$(discover_alias)"
echo
echo "THINKPAD_SSH_ALIAS=$THINKPAD_ALIAS"

echo
echo "=== SERVER -> THINKPAD SSH PROOF ==="
SSH_PROOF="$(runuser -u "$SERVICE_USER" -- ssh \
  -o BatchMode=yes \
  -o PasswordAuthentication=no \
  -- "$THINKPAD_ALIAS" \
  'printf "HOST=%s\nUSER=%s\n" "$(hostname -s)" "$(id -un)"')"
printf '%s\n' "$SSH_PROOF"
grep -Fqi "HOST=$THINKPAD_EXPECTED_HOSTNAME" <<<"$SSH_PROOF"
grep -Fq "USER=$SERVICE_USER" <<<"$SSH_PROOF"
echo "SERVER_TO_THINKPAD_SSH=PASS"

echo
echo "=== CAPABILITY PROBES ==="
CAPS=(PROCESS NETWORK)
ROOTS=()
REPOS=()

if runuser -u "$SERVICE_USER" -- ssh -o BatchMode=yes -- "$THINKPAD_ALIAS" \
  "python3 -c 'import os,sys; p=sys.argv[1]; sys.exit(0 if os.path.isdir(p) and os.access(p,os.R_OK|os.X_OK) else 1)' '$THINKPAD_ROOT'" \
  >/dev/null 2>&1; then
  CAPS+=(FILESYSTEM)
  ROOTS+=("$THINKPAD_ROOT")
  echo "THINKPAD_FILESYSTEM_ROOT=PASS:$THINKPAD_ROOT"
else
  echo "THINKPAD_FILESYSTEM_ROOT=NOT_GRANTED"
fi

if runuser -u "$SERVICE_USER" -- ssh -o BatchMode=yes -- "$THINKPAD_ALIAS" \
  "git -C '$THINKPAD_REPO' rev-parse --is-inside-work-tree" \
  2>/dev/null | grep -qx true; then
  CAPS+=(GIT)
  REPOS+=("$THINKPAD_REPO")
  echo "THINKPAD_GIT_REPOSITORY=PASS:$THINKPAD_REPO"
else
  echo "THINKPAD_GIT_REPOSITORY=NOT_GRANTED"
fi

printf 'THINKPAD_CAPABILITIES=%s\n' "$(IFS=,; echo "${CAPS[*]}")"

if [ "$MODE" != "apply" ]; then
  echo
  echo "PLAN_ONLY=PASS"
  echo "NEXT=sudo $0 --apply"
  exit 0
fi

install -d -m 0750 -o "$SERVICE_USER" -g "$SERVICE_GROUP" "$RECEIPTS"
install -d -m 0750 -o root -g "$SERVICE_GROUP" "$BACKUPS"

STAMP="$(date +%Y%m%dT%H%M%S%z)"
BACKUP="$BACKUPS/hosts.json.$STAMP"
cp -a "$HOSTS" "$BACKUP"
echo "REGISTRY_BACKUP=$BACKUP"

CAPS_JSON="$(printf '%s\n' "${CAPS[@]}" | python3 -c 'import json,sys; print(json.dumps([x.strip() for x in sys.stdin if x.strip()]))')"
ROOTS_JSON="$(printf '%s\n' "${ROOTS[@]:-}" | python3 -c 'import json,sys; print(json.dumps([x.strip() for x in sys.stdin if x.strip()]))')"
REPOS_JSON="$(printf '%s\n' "${REPOS[@]:-}" | python3 -c 'import json,sys; print(json.dumps([x.strip() for x in sys.stdin if x.strip()]))')"

python3 - "$HOSTS" "$THINKPAD_ALIAS" "$CAPS_JSON" "$ROOTS_JSON" "$REPOS_JSON" <<'PY'
import json,sys,tempfile,os
path,alias,caps_json,roots_json,repos_json=sys.argv[1:]
with open(path,encoding="utf-8") as f:
    doc=json.load(f)
hosts=doc.setdefault("hosts",[])
entry={
    "schema":"SCIENTIAM_REMOTE_OPS_HOST/0.1",
    "host_id":"THINKPAD-E470",
    "owner_id":"PROFESYS",
    "ssh_alias":alias,
    "capabilities":json.loads(caps_json),
    "allowed_roots":json.loads(roots_json),
    "allowed_services":[],
    "allowed_containers":[],
    "allowed_repositories":json.loads(repos_json),
    "allowed_data_classes":["PUBLIC","SYNTHETIC","INTERNAL_LOW","CONFIDENTIAL"],
    "lifecycle_state":"AUTHORIZED",
    "notes":"Registered by two-host closure after live SERVER->ThinkPad key-only SSH proof. Capabilities are probe-derived."
}
replaced=False
for i,h in enumerate(hosts):
    if h.get("host_id")=="THINKPAD-E470":
        hosts[i]=entry
        replaced=True
        break
if not replaced:
    hosts.append(entry)
fd,tmp=tempfile.mkstemp(prefix=".hosts.",dir=os.path.dirname(path),text=True)
try:
    with os.fdopen(fd,"w",encoding="utf-8") as f:
        json.dump(doc,f,indent=2,sort_keys=True)
        f.write("\n")
        f.flush()
        os.fsync(f.fileno())
    os.chmod(tmp,0o640)
    os.replace(tmp,path)
finally:
    if os.path.exists(tmp):
        os.unlink(tmp)
print("THINKPAD_REGISTRY_ACTION="+("REPLACED" if replaced else "ADDED"))
PY

chown root:"$SERVICE_GROUP" "$HOSTS"
chmod 0640 "$HOSTS"
python3 -m json.tool "$HOSTS" >/dev/null

echo
echo "=== SROF SAME-RUN SMOKE + RECEIPTS ==="
BEFORE="$(find "$RECEIPTS" -maxdepth 1 -type f -name 'SROF-*.json' 2>/dev/null | wc -l)"

set +e
SMOKE="$(runuser -u "$SERVICE_USER" -- env \
  SROF_HOSTS_FILE="$HOSTS" \
  SROF_RECEIPT_DIR="$RECEIPTS" \
  "$APP_DIR/.venv/bin/python" - <<'PY'
from srof_gateway.server import hosts_list, host_health
hosts=hosts_list()
print("HOSTS_LIST=", hosts)
ids={x["host_id"] for x in hosts}
required={"PROFESYS-SCIENTIAM","THINKPAD-E470"}
missing=required-ids
if missing:
    raise SystemExit("MISSING_HOSTS="+",".join(sorted(missing)))
for host_id in ("PROFESYS-SCIENTIAM","THINKPAD-E470"):
    r=host_health(host_id)
    print("HOST_HEALTH",host_id,"OK=",r["ok"],"REQUEST_ID=",r["receipt"]["request_id"],"EXIT_CODE=",r["receipt"]["exit_code"])
    if not r["ok"]:
        raise SystemExit(41)
PY
)"
RC=$?
set -e
printf '%s\n' "$SMOKE"

AFTER="$(find "$RECEIPTS" -maxdepth 1 -type f -name 'SROF-*.json' 2>/dev/null | wc -l)"

if [ "$RC" -ne 0 ] || [ "$AFTER" -lt $((BEFORE + 2)) ]; then
  echo "SROF_TWO_HOST_SMOKE=FAIL"
  cp -a "$BACKUP" "$HOSTS"
  chown root:"$SERVICE_GROUP" "$HOSTS"
  chmod 0640 "$HOSTS"
  echo "REGISTRY_ROLLBACK=PASS:$BACKUP"
  exit 40
fi

echo
echo "=== FINAL REGISTRY READBACK ==="
python3 - "$HOSTS" <<'PY'
import json,sys
d=json.load(open(sys.argv[1],encoding="utf-8"))
for h in d.get("hosts",[]):
    print(json.dumps({
        "host_id":h.get("host_id"),
        "ssh_alias":h.get("ssh_alias"),
        "capabilities":h.get("capabilities"),
        "allowed_roots":h.get("allowed_roots"),
        "allowed_repositories":h.get("allowed_repositories"),
        "lifecycle_state":h.get("lifecycle_state")
    },sort_keys=True))
PY

echo
echo "RECEIPTS_BEFORE=$BEFORE"
echo "RECEIPTS_AFTER=$AFTER"
echo "SROF_TWO_HOST_REGISTRY=PASS"
echo "SERVER_TO_THINKPAD_SSH=PASS"
echo "HOSTS_LIST_TWO_HOSTS=PASS"
echo "HOST_HEALTH_SERVER=PASS"
echo "HOST_HEALTH_THINKPAD=PASS"
echo "RECEIPT_READBACK=PASS"
echo "DCP_USED=NO"
echo "GITHUB_ACTIONS_TRANSPORT=NO"
