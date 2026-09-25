# ChatGPT ↔ SROF Exposure Runbook

**Status:** ACTIVE / BACKEND READY / CHATGPT BINDING PER-RUNTIME  
**Canonical remote MCP URL:** `https://srof.scientiam.com.ar/mcp`  
**Forbidden fallbacks:** DCP; GitHub Actions as remote transport

## Architecture

```text
ChatGPT custom MCP/app
  → https://srof.scientiam.com.ar/mcp
  → Cloudflare Tunnel
  → SROF OAuth Resource Server
  → host policy / receipts
  → governed OpenSSH
  → ThinkPad / SERVER

OAuth
  → https://auth.scientiam.com.ar/realms/scientiam-srof
  → Keycloak 26.7.4
  → Founder password + TOTP
```

No OpenAI Secure MCP Tunnel is required by the current canonical architecture.
No Cloudflare Access / Zero Trust is used.

## SROF endpoints

- MCP: `https://srof.scientiam.com.ar/mcp`
- protected-resource metadata: `https://srof.scientiam.com.ar/.well-known/oauth-protected-resource/mcp`
- OAuth issuer: `https://auth.scientiam.com.ar/realms/scientiam-srof`
- Keycloak public auth edge origin: `127.0.0.1:8097`
- Keycloak direct/local admin origin: `127.0.0.1:8096`
- Keycloak health: `127.0.0.1:9006`
- SROF local listener: `127.0.0.1:8765`
- receipts: `/var/lib/scientiam/remote-ops/receipts`

## OAuth requirements

- scope: `srof:read`
- audience/resource: `https://srof.scientiam.com.ar/mcp`
- PKCE: S256
- CIMD: enabled
- Founder MFA: password + TOTP
- anonymous MCP access: 401

## Registering SROF in a ChatGPT runtime

When the ChatGPT account/workspace exposes custom remote MCP/app registration:

1. Create or register an app named `SCIENTIAM SROF`.
2. Use remote MCP URL:
   `https://srof.scientiam.com.ar/mcp`
3. Use the product's OAuth discovery/authorization flow.
4. Complete Founder login.
5. Complete TOTP.
6. Scan/discover tools.
7. Verify at least:
   - `hosts_list`
   - `host_health`
8. Execute a read-only call.
9. Read back the SROF receipt.
10. Confirm receipt actor/client/scopes are populated.

Do not configure Cloudflare Access credentials or an OpenAI tunnel-client for the canonical path.

## Expected current tools

- `hosts_list`
- `host_health`
- `fs_list`
- `fs_read`
- `fs_find`
- `process_list`
- `service_status`
- `docker_ps`
- `docker_logs`
- `git_status`
- `git_diff`
- `journal_tail`
- `network_listeners`

Current surface is read-only.

## Acceptance gate for a ChatGPT binding

```text
SROF_REMOTE_ENDPOINT = PASS
OAUTH_DISCOVERY = PASS
FOUNDER_LOGIN_TOTP = PASS
CHATGPT_TOOL_SCAN = PASS
hosts_list = PASS
host_health = PASS
RECEIPT_ACTOR_BINDING = PASS
DCP_USED = NO
GITHUB_ACTIONS_TRANSPORT = NO
```

## Runtime rule for every chat

If `SCIENTIAM SROF` is exposed in the current runtime, use it for machine-access tasks.

If it is not exposed:

```text
TOOLING_GAP — STRAN/SROF no está expuesto en este runtime.
```

Do not select another remote transport.
