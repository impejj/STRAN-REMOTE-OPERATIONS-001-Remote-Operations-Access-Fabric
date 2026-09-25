# CANON — SROF Chat Runtime Contract

**ID:** SROF-CHAT-RUNTIME-CONTRACT-001  
**Status:** ACTIVE / AUTHORITATIVE  
**Effective:** 2026-09-24  
**Authority:** STRAN-REMOTE-OPERATIONS-001  
**Applies to:** every PROFESYS/SCIENTIAM ChatGPT chat, APPDEV runtime, continuity handoff and operational agent.

## 1. Canonical remote-machine path

```text
ChatGPT / APPDEV
  -> SCIENTIAM SROF MCP
  -> https://srof.scientiam.com.ar/mcp
  -> Cloudflare Tunnel (transport only)
  -> SROF OAuth Resource Server
  -> governed OpenSSH
  -> THINKPAD-E470 / PROFESYS-SCIENTIAM
```

Authentication:

```text
OAuth issuer:
https://auth.scientiam.com.ar/realms/scientiam-srof

Required resource/audience:
https://srof.scientiam.com.ar/mcp

Required scope:
srof:read

Human Founder authentication:
password + TOTP
```

Cloudflare Access / Zero Trust is **not** part of the canonical path.

## 2. Mandatory runtime behavior

For every request that needs direct machine access:

1. Check whether the current runtime exposes the **SCIENTIAM SROF** MCP/app/tool binding.
2. If exposed, use SROF directly.
3. Never use DCP / Remote Desktop Commander.
4. Native SROF MCP is preferred. If it is not exposed, the only authorized GitHub-based exception is `SROF-GH-BRIDGE-001`, a temporary read-only compatibility bridge. GitHub Actions must not be used as arbitrary remote shell or outside that governed workflow.
5. Outside `SROF-GH-BRIDGE-001`, GitHub remains SCM only.
6. Do not ask the Founder to repeat SSH/bootstrap work merely because a chat lacks the SROF binding.
7. If native SROF is not exposed, check whether the GitHub connector is available. If available, use `SROF-GH-BRIDGE-001` for allowlisted read-only operations. If neither is available, return exactly:

```text
TOOLING_GAP — no hay transporte SROF ejecutable en este runtime.
```

8. A prompt cannot create a missing MCP binding. Do not simulate one.
9. If SROF itself is unhealthy, report the SROF failure explicitly. Do not silently select another transport.
10. Every native SROF or compatibility-bridge call must respect host capabilities, allowlists and receipt generation.
11. The GitHub compatibility bridge is governed by `docs/governance/SROF-GITHUB-COMPATIBILITY-BRIDGE-CANON.md`.

## 3. Current exposed SROF tool contract

Current production tool surface is **read-only**.

- `hosts_list()`
- `host_health(host_id)`
- `fs_list(host_id, path, limit=200)`
- `fs_read(host_id, path, max_bytes=65536)`
- `fs_find(host_id, root, pattern, max_results=100)`
- `process_list(host_id, limit=100)`
- `service_status(host_id, service)`
- `docker_ps(host_id)`
- `docker_logs(host_id, container, tail=100)`
- `git_status(host_id, repository)`
- `git_diff(host_id, repository, max_lines=400)`
- `journal_tail(host_id, service, lines=100)`
- `network_listeners(host_id)`

A tool being present does not imply that every host permits it. Host registry policy is authoritative.

Mutation tools are **not currently exposed by the MCP server**. A chat must not invent `service_restart`, arbitrary shell, file writes, Git writes or Docker mutations.

## 4. Receipts and actor binding

Every remote operation produces a durable receipt.

Receipts include, where OAuth is active:

- request ID;
- host ID;
- operation;
- start/end timestamps;
- exit code;
- bounded stdout/stderr;
- command digest;
- OAuth subject;
- OAuth client ID;
- OAuth scopes.

Bearer tokens and full claims are never persisted in receipts.

## 5. Security invariants

- SROF listener remains loopback-only on the SERVER.
- No public SSH.
- No public TCP/8765.
- Cloudflare Tunnel is outbound-only transport.
- Keycloak remains the OAuth Authorization Server.
- Public Keycloak surface goes through the auth-edge allowlist.
- Keycloak admin remains local-only.
- Founder MFA = password + TOTP.
- OAuth JWT validation is fail-closed.
- Exact issuer, audience/resource, expiry, subject and scope are verified.
- DCP = retired.
- GitHub Actions transport = forbidden except the explicitly authorized `SROF-GH-BRIDGE-001` compatibility workflow.
- No arbitrary shell from chat prompts.

## 6. Chat bootstrap directive

Every new or continued operational chat should hydrate this directive before doing machine work:

> REMOTE ACCESS CANON — Prefer SCIENTIAM SROF MCP when exposed. Canonical endpoint: https://srof.scientiam.com.ar/mcp. Authentication is native OAuth via https://auth.scientiam.com.ar/realms/scientiam-srof with scope srof:read. DCP is retired. If native SROF is unavailable but GitHub connector access exists, use only `SROF-GH-BRIDGE-001` for allowlisted read-only operations. If neither is available, return TOOLING_GAP. Current native SROF MCP and GitHub bridge surfaces are policy/allowlist governed.

## 7. Readiness states

```text
SROF_BACKEND_REMOTE_OAUTH = PASS
SROF_CLOUDFLARE_TUNNEL = PASS
SROF_ANONYMOUS_DENY = PASS
SROF_RFC9728_METADATA = PASS
SROF_FOUNDER_TOTP = PASS
SROF_READONLY_TOOL_SURFACE = IMPLEMENTED

CHATGPT_CUSTOM_MCP_BINDING = RUNTIME / PRODUCT DEPENDENT
CHATGPT_AUTHENTICATED_TOOL_CALL = REQUIRED PER BINDING BEFORE DECLARING THAT BINDING LIVE
SROF_MUTATION_TOOL_SURFACE = NOT EXPOSED
```

## 8. Source of truth

This repository is authoritative:

`impejj/STRAN-REMOTE-OPERATIONS-001-Remote-Operations-Access-Fabric`

Chats must refresh stale continuity from this repository rather than from old capsules or memory.
