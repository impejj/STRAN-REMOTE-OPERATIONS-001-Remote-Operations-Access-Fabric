# EVIDENCE — SROF Remote OAuth Readiness — 2026-09-24

**Scope:** durable non-secret evidence of SROF remote-access readiness.

## Closed gates

```text
DEDICATED_CLOUDFLARE_TUNNEL = PASS
SROF_REMOTE_ROUTE = PASS
AUTH_REMOTE_ROUTE = PASS
SROF_LOOPBACK_ONLY = PASS
KEYCLOAK_READY = PASS
AUTH_EDGE_READY = PASS
OIDC_DISCOVERY = PASS
PKCE_S256 = PASS
CIMD = PASS
ANONYMOUS_MCP_DENY_401 = PASS
RFC9728_METADATA = PASS
OAUTH_RESOURCE_BINDING = PASS
OAUTH_SCOPE_ADVERTISEMENT = PASS
FOUNDER_PASSWORD = PASS
FOUNDER_TOTP = PASS
FOUNDER_AUTH_HUMAN_GATE = PASS
DCP_USED = NO
GITHUB_ACTIONS_TRANSPORT = NO
```

## Canonical endpoints

- MCP: `https://srof.scientiam.com.ar/mcp`
- OAuth issuer: `https://auth.scientiam.com.ar/realms/scientiam-srof`
- scope: `srof:read`
- audience/resource: `https://srof.scientiam.com.ar/mcp`

## Current tool authority

Implemented MCP surface is read-only.

Every tool remains subject to host-registry capability/allowlist checks and durable receipts.

## Remaining product/runtime gate

This evidence does **not** assert that every ChatGPT runtime automatically has the SROF tool binding.

A specific ChatGPT runtime is LIVE only after it:

1. exposes/registers `SCIENTIAM SROF`;
2. completes OAuth + TOTP;
3. discovers tools;
4. executes `hosts_list`;
5. executes an authorized `host_health`;
6. produces a receipt with OAuth actor/client/scope binding.

Until that per-runtime gate is closed, the correct response is:

```text
TOOLING_GAP — STRAN/SROF no está expuesto en este runtime.
```
