# SROF OpenAI Responses P0 Runbook

## Goal

Prove OpenAI API -> SROF MCP -> governed OpenSSH on both canonical hosts.

## Preflight

- SROF endpoint is reachable at `https://srof.scientiam.com.ar/mcp`.
- Run `sudo deploy/native-auth/configure-openai-responses-client.sh` once on PROFESYS-SCIENTIAM.
- Keycloak/SROF OAuth issues a token with `srof:read` and SROF audience.
- `OPENAI_API_KEY` and `OPENAI_MODEL` are injected through the runtime secret plane.
- The Founder completes browser password + TOTP; the PKCE access token stays in memory.
- No secret is copied into Git or durable chat artifacts.

## Execute

From `clients/openai-responses`:

```bash
python srof_openai_client.py --probe --json
# Browser opens -> Founder password + TOTP -> loopback callback -> token exchange -> live probe
```

## PASS

The response must contain MCP calls proving:

1. `hosts_list`.
2. `host_health` against `PROFESYS-SCIENTIAM`.
3. `host_health` against `THINKPAD-E470`.
4. No MCP call outside the read-only allowlist.
5. No MCP call has an error.
6. Matching SROF receipts exist server-side with actor/client/scope data.
7. DCP was not used.
8. GitHub Actions was not used as remote transport.

## Failure classification

- HTTP/API failure before MCP listing: `OPENAI_CLIENT_OR_CREDENTIAL_GAP`.
- MCP tool import/auth failure: `SROF_TOKEN_OR_MCP_AUTH_GAP`.
- Tool discovered but host unavailable: `SROF_HOST_PATH_GAP`.
- Tool succeeds but receipt lacks actor binding: `SROF_AUDIT_GAP`.
- Missing local ChatGPT tool binding is irrelevant to this adapter; it is specifically designed to bypass that product-surface dependency while preserving SROF.

## Rollback

There is no remote-host mutation in P0. Remove/disable the client runtime and revoke its SROF OAuth session/token. SROF and managed hosts remain unchanged.
