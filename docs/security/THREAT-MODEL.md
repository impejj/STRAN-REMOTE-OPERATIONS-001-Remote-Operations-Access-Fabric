# SROF Threat Model v0.1

## Assets
- host shell access;
- source code;
- secrets;
- production data;
- Docker/systemd control;
- remote desktop sessions;
- audit receipts.

## Primary threats
1. AI prompt or database payload becomes arbitrary shell.
2. Compromised client reuses long-lived SSH credentials.
3. Path traversal escapes allowed roots.
4. Sudo escalation bypasses policy.
5. Remote desktop exposes credentials or sensitive screens.
6. Logs leak secrets.
7. Contributor capacity is used outside owner authorization.
8. A write succeeds but verification fails silently.
9. SaaS/tunnel outage becomes a single point of failure.
10. MeshCentral or gateway is exposed without MFA/TLS/network restrictions.

## Controls
- allowlisted operation IDs, not free-form shell;
- per-host accounts and SSH keys/certs;
- `PermitRootLogin no`;
- `PasswordAuthentication no` after bootstrap validation;
- separate sudoers file with exact commands where needed;
- allowed filesystem roots + realpath/no-follow validation;
- bounded stdout/stderr with secret redaction;
- Control Registry authority envelope;
- pause/drain/revoke at channel level;
- post-condition readback mandatory for mutations;
- LAN-first deployment;
- MFA on human plane before WAN;
- encrypted backups of MeshCentral state;
- DCP retained only as temporary fallback.

## Stop conditions
Do not enable WAN exposure, root access, unrestricted shell, unattended production deletes, or external publication without explicit Founder/CISO approval.
