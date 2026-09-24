# CANON — Direct Machine Access

**ID:** STRAN-REMOTE-ACCESS-CANON-20260923  
**Status:** ACTIVE / AUTHORITATIVE  
**Effective:** 2026-09-24  
**Authority:** STRAN-REMOTE-OPERATIONS-001

## Decision

PROFESYS/SCIENTIAM no longer uses DCP / Remote Desktop Commander as an operational access path.

The canonical access model is direct machine access through the STRAN/SROF fabric, using governed OpenSSH identities and direct-access tooling.

## Mandatory behavior

1. Canonical path: **ChatGPT / APPDEV → STRAN/SROF → governed OpenSSH → ThinkPad / SERVER**.
2. **DCP / Remote Desktop Commander is RETIRED and MUST NOT be used.**
3. **GitHub Actions MUST NOT be used as a remote machine transport, bootstrap bridge or fallback.**
4. GitHub is SCM only: repositories, branches, commits, PRs, merges, tags, issues, code review and related native Git/source-management functions.
5. Never block remote work waiting for DCP quota/device state or GitHub Actions runner/workflow state.
6. Preserve least privilege, explicit identity, post-condition verification and durable evidence on STRAN/SROF.
7. If the ChatGPT/APPDEV runtime does not expose STRAN/SROF, return **TOOLING_GAP** and stop remote execution. Do not invent another transport.
8. If STRAN/SROF direct access itself is unhealthy, report the direct-access failure. Do not silently fall back to DCP, GitHub Actions or another channel.
9. Continuity prompts, runbooks, agents and chats must treat any DCP-first or GitHub-Actions-remote instruction as stale context.
10. Historical DCP/GitHub-Actions bootstrap references may remain only as migration evidence.

## Chat bootstrap

Every new or continued operational chat should hydrate this rule before executing infrastructure work:

> Remote access canon: ChatGPT / APPDEV → STRAN/SROF → governed OpenSSH → ThinkPad / SERVER. DCP is retired. GitHub Actions is not a remote transport. If SROF is not exposed in the current runtime, declare TOOLING_GAP.

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
- proposes DCP before direct SSH/STRAN access;
- proposes GitHub Actions/self-hosted runners/workflows as a remote transport;
- invents any transport fallback instead of declaring TOOLING_GAP.
