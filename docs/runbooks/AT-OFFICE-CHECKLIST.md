# SROF — At-office P0 checklist

## Rule

Do not disable DCP or current SSH/password paths during bootstrap. The new path is proved in parallel first.

## 1. SERVER snapshot

- [ ] hostname / IP recorded
- [ ] current SSH status recorded
- [ ] firewall/listeners recorded
- [ ] Docker health recorded
- [ ] DCP state recorded
- [ ] current backup/restore point verified

## 2. THINKPAD snapshot

Same checks as SERVER.

## 3. Prepare SSH identity

- [ ] dedicated `scientiam-remoteops` account exists
- [ ] dedicated public key installed
- [ ] key login verified from a second terminal
- [ ] host key fingerprint recorded
- [ ] no root login introduced
- [ ] current access path still works

## 4. Deploy MeshCentral LAN-first

```bash
cd deploy/meshcentral
cp .env.example /srv/scientiam/secrets/meshcentral.env
# edit external env; do not commit
docker compose --env-file /srv/scientiam/secrets/meshcentral.env up -d
```

Then:
- [ ] create first admin
- [ ] new account creation remains disabled after bootstrap
- [ ] MFA enabled
- [ ] SERVER agent enrolled
- [ ] THINKPAD agent enrolled
- [ ] terminal verified
- [ ] files verified
- [ ] desktop verified where supported
- [ ] backup of MeshCentral state configured

## 5. Configure gateway host registry

Copy `deploy/remote-ops/hosts.example.json` outside Git, populate exact service/container allowlists, and change lifecycle from `REGISTERED` only after verification.

## 6. P0 read-only smoke

For both hosts:
- [ ] hosts_list
- [ ] host_health
- [ ] service_status
- [ ] docker_ps where applicable
- [ ] git_status
- [ ] journal_tail
- [ ] receipt written

## 7. Controlled mutation smoke

Choose one non-critical allowlisted service.
- [ ] status before
- [ ] authorized restart
- [ ] status after
- [ ] receipt
- [ ] no unrelated service changed

## 8. DCP outage drill

Without using DCP:
- [ ] human terminal
- [ ] file transfer
- [ ] health
- [ ] logs
- [ ] service control
- [ ] receipt inspection

Only after all pass: propose `DCP -> FALLBACK_NON_CRITICAL`.
