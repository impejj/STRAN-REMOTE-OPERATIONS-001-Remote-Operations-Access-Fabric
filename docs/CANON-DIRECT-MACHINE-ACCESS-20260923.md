# CANON — Direct Machine Access

**ID:** STRAN-REMOTE-ACCESS-CANON-20260923  
**Status:** ACTIVE / AUTHORITATIVE  
**Effective:** 2026-09-23  
**Authority:** STRAN-REMOTE-OPERATIONS-001

## Decision

PROFESYS/SCIENTIAM no longer uses DCP / Remote Desktop Commander as an operational access path.

The canonical access model is direct machine access through the STRAN/SROF fabric, using governed OpenSSH identities and direct-access tooling.

## Mandatory behavior

1. Never block work waiting for DCP availability, quota, device registration or session state.
2. Never propose DCP as the normal route to ThinkPad, SERVER or other registered nodes.
3. Use direct STRAN/SROF access first.
4. Preserve least privilege, explicit identity, post-condition verification and durable evidence.
5. If direct access is unavailable, report the direct-access failure; do not silently fall back to DCP.
6. Continuity prompts, runbooks, agents and chats must treat any DCP-first instruction as stale context.
7. DCP may be mentioned only in historical migration evidence.

## Chat bootstrap

Every new or continued operational chat should hydrate this rule before executing infrastructure work:

> Remote access is STRAN/SROF direct access. DCP/Remote Desktop Commander is retired and must not be used.

## Scope

Applies to:
- PROFESYS website operations;
- SCIENTIAM services;
- SEF workers;
- STRAN workflows;
- HCE operational labs;
- server and ThinkPad administration;
- deployment, QA, diagnostics and evidence collection.

## Supersedes

Any prior note, capsule or continuity prompt that:
- describes DCP as fallback;
- waits for DCP quota reset;
- asks whether DCP is online;
- proposes DCP before direct SSH/STRAN access.
