# STRAN-REMOTE-OPERATIONS-001 — Remote Operations & Access Fabric

**Status:** ACTIVE · P0  
**Canonical authority:** this repository  
**Scope:** governed remote operations for SCIENTIAM/PROFESYS infrastructure  
**Implementation codename:** SROF — SCIENTIAM Remote Operations Fabric

## Mission

Provide resilient, auditable and self-hosted remote operations so SCIENTIAM is not operationally dependent on quota-bound third-party remote-control services.

## Architecture

Two independent planes:

1. **Human Operations Plane** — interactive browser-based remote administration.
2. **AI Operations Plane** — governed MCP/OpenSSH access with policy enforcement, bounded tools, verification and durable receipts.

**DCP / Desktop Commander Remote is retired from the operational path.** It is neither the canonical control plane nor an approved fallback for normal PROFESYS/SCIENTIAM work. Remote execution must use the direct STRAN/SROF access fabric (OpenSSH and governed direct-access tooling).

## Canonical boundaries

- **STRAN-REMOTE-OPERATIONS-001** = transversal responsibility and governance.
- **SROF** = implementation/platform for that responsibility.
- **This repository** = technical source of truth.
- **profesys-scientiam** = historical origin and downstream integrator/consumer.
- **ChatGPT Control Tower** = decision and continuity surface; not code authority.

## Non-negotiable security invariants

- no direct AI root access;
- no secrets or private keys in Git;
- no arbitrary shell sourced from queues/databases;
- least privilege and explicit allowlists;
- key-based remote identity after bootstrap verification;
- every mutation requires post-condition verification and a durable receipt;
- publication/external exposure is a separate authority gate.

## P0 objective

Loss or unavailability of any third-party remote-control service must not block:

- terminal access;
- file transfer;
- host health inspection;
- service status and controlled restart;
- Docker/Git/log inspection;
- evidence collection.

## Migration history

The initial implementation was created in `impejj/profesys-scientiam` through:

- Issue #549 — P0 replacement of quota-bound DCP;
- PR #550 — SROF foundation;
- PR #556 — operator kit and read-only gateway expansion.

Those artifacts remain historical evidence. Active development moves here.

## Repository layout

```
docs/        architecture, governance, security, runbooks, migration
gateway/     governed MCP/OpenSSH remote operations gateway
deploy/      MeshCentral, SSH and remote-ops deployment assets
registry/    schemas and examples for governed host registration
tests/       integration/smoke validation
evidence/    non-secret evidence conventions and receipts metadata
.github/     CI and repository automation
```

## Immediate gates

1. Canonical migration from `profesys-scientiam`.
2. SERVER + ThinkPad preflight.
3. MeshCentral LAN-first deployment.
4. Dedicated OpenSSH identities.
5. SROF gateway deployment and read-only smoke tests.
6. Controlled mutation verification.
7. Direct-access outage/recovery drill.
8. Verify that no operational runbook, chat continuity prompt or worker bootstrap still depends on DCP.


## Canonical chat/runtime directive — 2026-09-24

This rule is mandatory for every PROFESYS/SCIENTIAM chat, worker, runbook and continuity handoff.

### Canonical machine-access path

```text
ChatGPT / APPDEV
→ SCIENTIAM SROF MCP
→ https://srof.scientiam.com.ar/mcp
→ Cloudflare Tunnel (transport only)
→ SROF native OAuth Resource Server
→ governed OpenSSH
→ ThinkPad / SERVER
```

OAuth authority:

`https://auth.scientiam.com.ar/realms/scientiam-srof`

Required scope:

`srof:read`

### Mandatory runtime rules

- DCP / Remote Desktop Commander: **RETIRED / DO NOT USE**.
- GitHub Actions as remote transport: **DO NOT USE**.
- GitHub is SCM only.
- Cloudflare Access / Zero Trust is not part of the canonical SROF path.
- Current MCP tool surface is read-only and host-policy governed.
- If the current ChatGPT/APPDEV runtime exposes `SCIENTIAM SROF`, use it.
- If it does not expose the binding, return:

```text
TOOLING_GAP — STRAN/SROF no está expuesto en este runtime.
```

- Never invent DCP, raw SSH, GitHub Actions or another transport fallback.
- A prompt cannot create a missing MCP binding.

### Authoritative runtime specification

Read before machine operations:

- `docs/governance/SROF-CHAT-RUNTIME-CONTRACT.md`
- `docs/governance/SROF-REMOTE-MCP-ACCESS-CANON.md`
- `docs/governance/SROF-CHATGPT-TOOL-EXPOSURE-GATE.md`
- `docs/runbooks/CHATGPT-SROF-EXPOSURE.md`
- `docs/runbooks/SROF-NATIVE-OAUTH.md`

This directive supersedes all earlier bootstrap wording that described DCP, GitHub Actions, Cloudflare Access or OpenAI Secure MCP Tunnel as the canonical machine-access path.
