# SROF Fast Gate — SERVER ↔ THINKPAD

Purpose: finish the last mile from a proven OpenSSH transport to a governed SROF gateway without using DCP.

## Already proven

The server-to-ThinkPad dedicated SSH path has passed with the `scientiam-remoteops` identity and the ThinkPad SSH service active.

Do not remove DCP yet. It remains fallback until the gateway, channel registration and outage drill are complete.

## 1. Verify transport from SERVER

Use the configured SROF SSH alias if present:

```bash
ssh -o BatchMode=yes thinkpad-e470-srof 'printf "SROF_SSH_PASS host=%s user=%s\n" "$(hostname -s)" "$(id -un)"'
```

If the alias is not yet installed, use the existing dedicated identity/configuration prepared outside Git. Do not paste private keys into chat, Git or logs.

## 2. Create the live host registry outside Git

Target:

```text
/etc/scientiam/remote-ops/hosts.json
```

Base it on `deploy/remote-ops/hosts.example.json`.

Required before activation:
- SERVER and THINKPAD host IDs;
- verified SSH aliases;
- exact allowed roots;
- exact allowlisted repositories;
- only the services/containers actually required;
- lifecycle state at least `AUTHORIZED`.

No credentials or private keys belong in the registry.

## 3. Prepare gateway on SERVER

From the canonical STRAN repository checkout:

```bash
sudo ./deploy/remote-ops/prepare-gateway-server.sh prepare
sudo ./deploy/remote-ops/prepare-gateway-server.sh status
```

Preparation copies the gateway, creates the isolated venv and systemd unit, but does not start the service if the live registry is missing.

## 4. Activate only after registry review

```bash
sudo ./deploy/remote-ops/prepare-gateway-server.sh activate
sudo ./deploy/remote-ops/prepare-gateway-server.sh status
```

Expected:
- service = active;
- no root runtime;
- receipt directory writable only by the service identity;
- host registry read from `/etc/scientiam/remote-ops/hosts.json`.

## 5. Read-only smoke

Run the gateway functions against THINKPAD:
- `hosts_list`;
- `host_health`;
- `fs_list` on one approved root;
- `git_status` on one approved repository;
- `process_list`;
- `network_listeners`.

Then deliberately request one path outside the approved roots. The request must fail closed.

## 6. Evidence gate

Verify at least one receipt exists under:

```text
/var/lib/scientiam/remote-ops/receipts
```

A success without a durable receipt is not `EVIDENCE_OK`.

## 7. Control-plane registration

Project the sanitized channel contract from `registry/channels.example.json` into the SCIENTIAM control plane:

- `CHANNEL-SERVER-REMOTEOPS-001`
- `CHANNEL-THINKPAD-REMOTEOPS-001`

Do not transfer STRAN ownership to a consumer.

## Exit condition for this fast gate

The gate is complete when:
- SERVER → THINKPAD SSH still passes;
- SROF gateway is active;
- approved read-only tools pass;
- a denied operation fails closed;
- receipts exist;
- both channels are registered.

Only after the separate DCP outage drill and five consecutive sessions without DCP may DCP be demoted to `FALLBACK_NON_CRITICAL`.
