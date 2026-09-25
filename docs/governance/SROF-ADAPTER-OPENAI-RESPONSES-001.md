# SROF-ADAPTER-OPENAI-RESPONSES-001

**Status:** IMPLEMENTED_P0 / LIVE_VALIDATION_REQUIRED  
**Authority:** STRAN-REMOTE-OPERATIONS-001  
**Purpose:** bind OpenAI API workloads to the existing SROF MCP control plane without DCP or GitHub Actions transport.

## Architecture

```text
SCIENTIAM UI / CLI / AIPS
  -> OpenAI Responses API
  -> remote MCP server_url=https://srof.scientiam.com.ar/mcp
  -> SROF OAuth Resource Server
  -> host policy + receipts
  -> governed OpenSSH
  -> managed hosts
```

This is an adapter, not a new control plane. SROF remains the single authority for host policy, tools and receipts.

## Current OpenAI contract

The Responses API supports remote MCP tools by `server_url`. Authenticated MCP servers receive an OAuth bearer through the MCP tool's `authorization` field. Tool discovery can be narrowed with `allowed_tools`, and approval behavior can be controlled with `require_approval`.

## P0 policy

Allowed tools are exactly the current SROF read-only surface:

- hosts_list
- host_health
- fs_list
- fs_read
- fs_find
- process_list
- service_status
- docker_ps
- docker_logs
- git_status
- git_diff
- journal_tail
- network_listeners

No mutation tool is permitted by this adapter.

## Secret boundary

Required persistent runtime secret:

- `OPENAI_API_KEY`

SROF authentication uses Founder Authorization Code + PKCE through the static native client
`srof-openai-responses-cli`. Password, TOTP, authorization code and bearer token MUST remain
outside Git, prompts, receipts and ordinary logs. The bearer remains in process memory.

For controlled diagnostics, `SROF_ACCESS_TOKEN` may be injected through the secret plane,
but it is not the normal P0 login path.

The SROF token must be issued for:

- issuer: `https://auth.scientiam.com.ar/realms/scientiam-srof`
- audience/resource: `https://srof.scientiam.com.ar/mcp`
- scope: `srof:read`

## Remaining LIVE gate

```text
CLIENT_CODE = PASS
OPENAI_API_CREDENTIAL = REQUIRED_AT_RUNTIME
SROF_PKCE_CLIENT_CONFIG = IMPLEMENTED / DEPLOY_REQUIRED
FOUNDER_PASSWORD_TOTP_FLOW = IMPLEMENTED_CLIENT_SIDE / LIVE_VALIDATION_REQUIRED
OPENAI_MCP_TOOL_IMPORT = PENDING_LIVE_PROBE
hosts_list = PENDING_LIVE_PROBE
host_health(PROFESYS-SCIENTIAM) = PENDING_LIVE_PROBE
host_health(THINKPAD-E470) = PENDING_LIVE_PROBE
SROF_RECEIPT_ACTOR_BINDING = PENDING_LIVE_PROBE
DCP_USED = NO
GITHUB_ACTIONS_TRANSPORT = NO
```

## Next increment

Implement a dedicated SROF OAuth token broker/session layer so the SCIENTIAM UI can perform Founder login + MFA and refresh tokens without exposing tokens to model-generated code.
