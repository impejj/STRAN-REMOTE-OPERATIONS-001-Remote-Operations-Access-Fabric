# SROF Founder OAuth Recovery — 2026-09-24

Status: **PASS**

## Scope
Metadata-only verification record for governed Founder OAuth credential recovery on the STRAN/SROF native-auth plane.

## Target
- target_class: SERVER native-auth / Keycloak
- container: native-auth-keycloak-1
- realm: scientiam-srof
- recovery_helper: deploy/native-auth/reset-founder-password.sh
- helper_commit: 181821cbc1cc0914c78ca178cd79fcd09fa1a3c8

## Verification
Observed non-secret terminal states:
- KEYCLOAK_CONTAINER=PASS
- KEYCLOAK_ADMIN_LOGIN=PASS
- FOUNDER_USER_PRESENT=PASS
- FOUNDER_PASSWORD_RESET=PASS
- FOUNDER_BRUTE_FORCE_STATE_CLEARED=PASS
- FOUNDER_TOTP_REQUIRED=PASS
- FOUNDER_PASSWORD_CREDENTIAL=PASS
- SECRETS_PRINTED=NO
- FOUNDER_PASSWORD_RECOVERY=PASS

## Security properties
- no Founder password committed to Git;
- no bootstrap admin secret printed;
- host `keycloak.env` was not read by the unprivileged operator;
- recovery used the already-running Keycloak container and its injected bootstrap environment;
- the operator did not require host sudo for this recovery path.

## Result
Founder OAuth recovery path is operational on SERVER without dependency on the SERVER sudo password.

Protected raw terminal evidence remains outside Git.
