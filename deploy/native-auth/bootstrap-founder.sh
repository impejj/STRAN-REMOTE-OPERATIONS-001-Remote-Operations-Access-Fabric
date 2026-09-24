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

test -r "$ENV_FILE"
set -a
# shellcheck disable=SC1090
. "$ENV_FILE"
set +a

read -r -p "Founder login email: " FOUNDER_EMAIL
if ! [[ "$FOUNDER_EMAIL" =~ ^[^[:space:]@]+@[^[:space:]@]+\.[^[:space:]@]+$ ]]; then
  echo "BLOCKED: invalid email" >&2
  exit 10
fi
read -r -s -p "Founder OAuth password (minimum 16 characters): " FOUNDER_PASS
echo
read -r -s -p "Repeat Founder OAuth password: " FOUNDER_PASS_2
echo
if [ "$FOUNDER_PASS" != "$FOUNDER_PASS_2" ] || [ "${#FOUNDER_PASS}" -lt 16 ]; then
  echo "BLOCKED: passwords differ or are shorter than 16 characters" >&2
  exit 11
fi

KC=(docker compose --env-file "$ENV_FILE" -f "$COMPOSE" exec -T keycloak /opt/keycloak/bin/kcadm.sh)
"${KC[@]}" config credentials --server http://localhost:8080 --realm master --user "$KC_BOOTSTRAP_ADMIN_USERNAME" --password "$KC_BOOTSTRAP_ADMIN_PASSWORD" >/dev/null

USER_ID="$("${KC[@]}" get users -r "$REALM" -q "username=$FOUNDER_EMAIL" --fields id,username --format csv --noquotes 2>/dev/null | awk -F, -v u="$FOUNDER_EMAIL" '$2==u{print $1; exit}')"
if [ -z "$USER_ID" ]; then
  "${KC[@]}" create users -r "$REALM" -s "username=$FOUNDER_EMAIL" -s "email=$FOUNDER_EMAIL" -s enabled=true -s emailVerified=true >/dev/null
  USER_ID="$("${KC[@]}" get users -r "$REALM" -q "username=$FOUNDER_EMAIL" --fields id,username --format csv --noquotes | awk -F, -v u="$FOUNDER_EMAIL" '$2==u{print $1; exit}')"
  echo "FOUNDER_USER_CREATED=YES"
else
  echo "FOUNDER_USER_CREATED=NO_REUSED"
fi

test -n "$USER_ID"
"${KC[@]}" set-password -r "$REALM" --userid "$USER_ID" --new-password "$FOUNDER_PASS" >/dev/null
unset FOUNDER_PASS FOUNDER_PASS_2 KC_BOOTSTRAP_ADMIN_PASSWORD KC_DB_PASSWORD
"${KC[@]}" update "users/$USER_ID" -r "$REALM" -s 'requiredActions=["CONFIGURE_TOTP"]' >/dev/null
echo "FOUNDER_PASSWORD_SET=PASS"
echo "FOUNDER_TOTP_REQUIRED=PASS"
echo "FOUNDER_EMAIL=$FOUNDER_EMAIL"
echo "FOUNDER_USER_ID=$USER_ID"
