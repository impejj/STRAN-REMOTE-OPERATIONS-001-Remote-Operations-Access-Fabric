# SROF P0 Implementation Runbook

## At-office objective

Leave the office with two independent paths:
1. human browser access through MeshCentral;
2. AI/automation access through OpenSSH + SROF Gateway.

## Phase A — preflight

On SERVER and THINKPAD:

```bash
hostnamectl
ip -br addr
ss -ltnp
systemctl is-active ssh
ssh -V
docker --version
```

Record:
- hostnames;
- LAN IPs;
- current SSH state;
- current firewall;
- current DCP state;
- backup/restore point.

## Phase B — SSH baseline

Create dedicated service identity, for example `scientiam-remoteops`.

Principles:
- no root login;
- key-only authentication;
- separate key per control client/channel;
- explicit `authorized_keys`;
- narrow sudoers commands only when required.

Do not disable password auth until a second terminal has proved key login and sudo path.

## Phase C — MeshCentral

Use `deploy/meshcentral/compose.yml`.

1. copy `.env.example` to an external secret/env location;
2. choose LAN hostname/IP first;
3. start MeshCentral;
4. create the first admin account;
5. immediately disable new account creation;
6. enable MFA;
7. install agents on SERVER and THINKPAD;
8. verify terminal, files and desktop where supported;
9. back up MeshCentral data.

## Phase D — SROF Gateway

1. create external host registry from the schema;
2. configure SSH aliases;
3. run gateway locally;
4. test read-only tools;
5. enable one mutation at a time;
6. validate receipt + readback.

## Phase E — Slot Control Plane

Register:
- `CHANNEL-SERVER-REMOTEOPS-001`
- `CHANNEL-THINKPAD-REMOTEOPS-001`

Then prove:
`Activity Request -> slot -> channel -> SROF tool -> receipt`.

## Phase F — DCP exit drill

Simulate DCP unavailable.

Acceptance:
- human terminal works;
- file transfer works;
- host health works;
- service status works;
- controlled restart works;
- receipt exists.

Only then mark DCP `FALLBACK_NON_CRITICAL`.
