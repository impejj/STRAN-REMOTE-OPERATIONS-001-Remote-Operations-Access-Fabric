#!/usr/bin/env bash
set -euo pipefail

MODE="plan"
SERVICE_USER="${SROF_SERVICE_USER:-scientiam-remoteops}"
SERVICE_GROUP="${SROF_SERVICE_GROUP:-scientiam-remoteops}"
SERVICE_HOME="${SROF_SERVICE_HOME:-/home/$SERVICE_USER}"
ETC_DIR="${SROF_ETC_DIR:-/etc/scientiam/remote-ops}"
HOSTS="${SROF_HOSTS_FILE:-$ETC_DIR/hosts.json}"
STATE_DIR="${SROF_STATE_DIR:-/var/lib/scientiam/remote-ops}"
RECEIPTS="${SROF_RECEIPT_DIR:-$STATE_DIR/receipts}"
BACKUPS="$STATE_DIR/registry-backups"
APP_DIR="${SROF_APP_DIR:-/opt/scientiam/remote-ops-gateway}"

SERVER_HOST_ID="PROFESYS-SCIENTIAM"
THINKPAD_HOST_ID="THINKPAD-E470"
THINKPAD_IP="${THINKPAD_IP:-192.168.1.6}"
THINKPAD_EXPECTED_HOSTNAME="${THINKPAD_EXPECTED_HOSTNAME:-thinkPad-E470}"
THINKPAD_EXPECTED_HOSTKEY="${THINKPAD_EXPECTED_HOSTKEY:-SHA256:IlyXHNcmKV2hBq+oIny/tH+V6RC8QtQgBie8jEh0MBg}"
THINKPAD_ALIAS="${THINKPAD_SSH_ALIAS:-thinkpad-e470-srof}"
THINKPAD_ROOT="${THINKPAD_ALLOWED_ROOT:-/home/impejj/work/profesys}"
THINKPAD_REPO="${THINKPAD_ALLOWED_REPOSITORY:-/home/impejj/work/profesys/scientiam}"

GATEWAY_KEY="$SERVICE_HOME/.ssh/srof_gateway_to_thinkpad"
SSH_CONFIG="$SERVICE_HOME/.ssh/config"
KNOWN_HOSTS="$SERVICE_HOME/.ssh/known_hosts"

# Existing proven operator transport. Used only to bootstrap the gateway's
# independent public key onto the ThinkPad. The gateway never uses this key.
OPERATOR_KEY="${SROF_OPERATOR_BOOTSTRAP_KEY:-/home/profesys/.ssh/stran_remoteops_server_to_thinkpad}"

usage() {
  cat <<'EOF'
Usage:
  sudo deploy/remote-ops/close-two-host-registry.sh
  sudo deploy/remote-ops/close-two-host-registry.sh --apply

Default is PLAN/DIAGNOSTIC only.

The closure deliberately separates:
  1) proven operator SERVER -> ThinkPad transport;
  2) gateway-owned SERVER -> ThinkPad identity;
  3) SROF host-registry enrollment;
  4) SROF same-run host_health + durable receipts.

--apply is fail-closed and reversible for the host registry. It:
  - verifies the previously recorded ThinkPad ED25519 host fingerprint;
  - verifies the existing operator public-key-only channel;
  - creates/reuses a gateway-owned Ed25519 key under scientiam-remoteops;
  - installs only that public key on ThinkPad scientiam-remoteops;
  - installs a strict SSH alias for the gateway service account;
  - verifies gateway-account key-only SSH;
  - backs up hosts.json;
  - upserts THINKPAD-E470 without replacing SERVER;
  - grants FILESYSTEM/GIT only if live probes pass;
  - executes hosts_list + host_health for SERVER and ThinkPad;
  - requires two new durable SROF receipts;
  - restores the previous registry if the SROF smoke fails.

This script does NOT:
  - copy/reuse the operator private key for the gateway;
  - change sshd, firewall, sudoers, DCP, Cloudflare or GitHub Actions;
  - expose SSH or TCP/8765 publicly.
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
command -v ssh-keygen >/dev/null
command -v ssh-keyscan >/dev/null
command -v python3 >/dev/null
test -x "$APP_DIR/.venv/bin/python"
test -r "$HOSTS"
python3 -m json.tool "$HOSTS" >/dev/null

if [ "$MODE" = "apply" ]; then
  install -d -m 0700 -o "$SERVICE_USER" -g "$SERVICE_GROUP" "$SERVICE_HOME/.ssh"
elif [ ! -d "$SERVICE_HOME/.ssh" ]; then
  echo "GATEWAY_SSH_DIR=ABSENT_WILL_CREATE_ON_APPLY"
fi

echo
echo "=== CURRENT REGISTRY ==="
python3 - "$HOSTS" <<'PY'
import json,sys
d=json.load(open(sys.argv[1],encoding="utf-8"))
for h in d.get("hosts",[]):
    print("HOST_ID=%s SSH_ALIAS=%s LIFECYCLE=%s CAPABILITIES=%s" % (
        h.get("host_id"), h.get("ssh_alias"), h.get("lifecycle_state"),
        ",".join(h.get("capabilities",[]))
    ))
PY

echo
echo "=== THINKPAD HOST-KEY PIN ==="
SCAN_FILE="$(mktemp)"
trap 'rm -f "$SCAN_FILE"' EXIT
ssh-keyscan -T 5 -t ed25519 "$THINKPAD_IP" 2>/dev/null > "$SCAN_FILE"
test -s "$SCAN_FILE"
OBSERVED_FP="$(ssh-keygen -lf "$SCAN_FILE" -E sha256 | awk 'NR==1{print $2}')"
echo "THINKPAD_HOSTKEY_OBSERVED=$OBSERVED_FP"
echo "THINKPAD_HOSTKEY_EXPECTED=$THINKPAD_EXPECTED_HOSTKEY"
if [ "$OBSERVED_FP" != "$THINKPAD_EXPECTED_HOSTKEY" ]; then
  echo "BLOCKED: ThinkPad host fingerprint mismatch" >&2
  exit 21
fi
echo "THINKPAD_HOSTKEY_PIN=PASS"

echo
echo "=== EXISTING OPERATOR CHANNEL PROOF ==="
if [ ! -r "$OPERATOR_KEY" ]; then
  echo "BLOCKED: proven operator bootstrap key not readable: $OPERATOR_KEY" >&2
  exit 22
fi

OPERATOR_PROOF="$(ssh \
  -i "$OPERATOR_KEY" \
  -o IdentitiesOnly=yes \
  -o BatchMode=yes \
  -o PasswordAuthentication=no \
  -o StrictHostKeyChecking=yes \
  -o UserKnownHostsFile="$SCAN_FILE" \
  -o ConnectTimeout=5 \
  -- "$SERVICE_USER@$THINKPAD_IP" \
  'printf "HOST=%s\nUSER=%s\n" "$(hostname -s)" "$(id -un)"')"
printf '%s\n' "$OPERATOR_PROOF"
grep -Fqi "HOST=$THINKPAD_EXPECTED_HOSTNAME" <<<"$OPERATOR_PROOF"
grep -Fq "USER=$SERVICE_USER" <<<"$OPERATOR_PROOF"
echo "OPERATOR_SERVER_TO_THINKPAD=PASS"

gateway_ready=0
if [ -r "$GATEWAY_KEY" ] && [ -r "$SSH_CONFIG" ]; then
  if runuser -u "$SERVICE_USER" -- ssh \
    -o BatchMode=yes \
    -o PasswordAuthentication=no \
    -o ConnectTimeout=5 \
    -- "$THINKPAD_ALIAS" \
    'test "$(id -un)" = "scientiam-remoteops" && hostname -s' 2>/dev/null \
    | grep -Fqi "$THINKPAD_EXPECTED_HOSTNAME"; then
    gateway_ready=1
  fi
fi

echo
echo "=== GATEWAY IDENTITY STATE ==="
if [ "$gateway_ready" -eq 1 ]; then
  echo "GATEWAY_TO_THINKPAD=PASS_EXISTING"
else
  echo "GATEWAY_TO_THINKPAD=NEEDS_BOOTSTRAP"
  echo "GATEWAY_KEY=$GATEWAY_KEY"
  echo "GATEWAY_ALIAS=$THINKPAD_ALIAS"
fi

if [ "$MODE" != "apply" ]; then
  echo
  echo "PLAN_ONLY=PASS"
  if [ "$gateway_ready" -eq 1 ]; then
    echo "NEXT=sudo $0 --apply"
  else
    echo "NEXT=sudo $0 --apply  # bootstraps gateway-owned key, then closes registry"
  fi
  exit 0
fi

if [ "$gateway_ready" -ne 1 ]; then
  echo
  echo "=== BOOTSTRAP GATEWAY-OWNED THINKPAD IDENTITY ==="

  if [ ! -f "$GATEWAY_KEY" ]; then
    runuser -u "$SERVICE_USER" -- ssh-keygen \
      -t ed25519 -a 100 -N "" \
      -f "$GATEWAY_KEY" \
      -C "STRAN-REMOTE-OPERATIONS-001 gateway-to-thinkpad"
    echo "GATEWAY_KEY_CREATED=YES"
  else
    echo "GATEWAY_KEY_CREATED=NO_REUSED"
  fi
  chown "$SERVICE_USER:$SERVICE_GROUP" "$GATEWAY_KEY" "$GATEWAY_KEY.pub"
  chmod 0600 "$GATEWAY_KEY"
  chmod 0644 "$GATEWAY_KEY.pub"

  cat "$GATEWAY_KEY.pub" | ssh \
    -i "$OPERATOR_KEY" \
    -o IdentitiesOnly=yes \
    -o BatchMode=yes \
    -o PasswordAuthentication=no \
    -o StrictHostKeyChecking=yes \
    -o UserKnownHostsFile="$SCAN_FILE" \
    -o ConnectTimeout=5 \
    -- "$SERVICE_USER@$THINKPAD_IP" \
    'set -eu
     umask 077
     mkdir -p "$HOME/.ssh"
     touch "$HOME/.ssh/authorized_keys"
     chmod 700 "$HOME/.ssh"
     chmod 600 "$HOME/.ssh/authorized_keys"
     IFS= read -r key
     if grep -qxF "$key" "$HOME/.ssh/authorized_keys"; then
       echo GATEWAY_PUBLIC_KEY_INSTALLED=NO_ALREADY_PRESENT
     else
       printf "%s\n" "$key" >> "$HOME/.ssh/authorized_keys"
       echo GATEWAY_PUBLIC_KEY_INSTALLED=YES
     fi'

  touch "$KNOWN_HOSTS"
  chown "$SERVICE_USER:$SERVICE_GROUP" "$KNOWN_HOSTS"
  chmod 0600 "$KNOWN_HOSTS"
  while IFS= read -r line; do
    grep -qxF "$line" "$KNOWN_HOSTS" || printf '%s\n' "$line" >> "$KNOWN_HOSTS"
  done < "$SCAN_FILE"

  touch "$SSH_CONFIG"
  chown "$SERVICE_USER:$SERVICE_GROUP" "$SSH_CONFIG"
  chmod 0600 "$SSH_CONFIG"

  CONFIG_TMP="$(mktemp)"
  awk '
    /^# BEGIN SCIENTIAM SROF THINKPAD$/ {skip=1; next}
    /^# END SCIENTIAM SROF THINKPAD$/   {skip=0; next}
    !skip {print}
  ' "$SSH_CONFIG" > "$CONFIG_TMP"

  cat >> "$CONFIG_TMP" <<EOF

# BEGIN SCIENTIAM SROF THINKPAD
Host $THINKPAD_ALIAS
    HostName $THINKPAD_IP
    User $SERVICE_USER
    IdentityFile $GATEWAY_KEY
    IdentitiesOnly yes
    BatchMode yes
    PasswordAuthentication no
    StrictHostKeyChecking yes
    UserKnownHostsFile $KNOWN_HOSTS
    ServerAliveInterval 30
    ServerAliveCountMax 3
# END SCIENTIAM SROF THINKPAD
EOF

  install -m 0600 -o "$SERVICE_USER" -g "$SERVICE_GROUP" "$CONFIG_TMP" "$SSH_CONFIG"
  rm -f "$CONFIG_TMP"
fi

echo
echo "=== GATEWAY ACCOUNT -> THINKPAD PROOF ==="
SSH_PROOF="$(runuser -u "$SERVICE_USER" -- ssh \
  -o BatchMode=yes \
  -o PasswordAuthentication=no \
  -o ConnectTimeout=5 \
  -- "$THINKPAD_ALIAS" \
  'printf "HOST=%s\nUSER=%s\n" "$(hostname -s)" "$(id -un)"')"
printf '%s\n' "$SSH_PROOF"
grep -Fqi "HOST=$THINKPAD_EXPECTED_HOSTNAME" <<<"$SSH_PROOF"
grep -Fq "USER=$SERVICE_USER" <<<"$SSH_PROOF"
echo "GATEWAY_TO_THINKPAD=PASS"

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
    "notes":"Gateway-owned key-only SSH verified; capabilities are live probe-derived."
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
echo "OPERATOR_SERVER_TO_THINKPAD=PASS"
echo "GATEWAY_TO_THINKPAD=PASS"
echo "HOSTS_LIST_TWO_HOSTS=PASS"
echo "HOST_HEALTH_SERVER=PASS"
echo "HOST_HEALTH_THINKPAD=PASS"
echo "RECEIPT_READBACK=PASS"
echo "DCP_USED=NO"
echo "GITHUB_ACTIONS_TRANSPORT=NO"
