# CANON — SROF Remote MCP Access

**Status:** ACTIVE / REMOTE-OAUTH-READY  
**Authority:** STRAN-REMOTE-OPERATIONS-001

## Canonical architecture

```text
Authorized MCP client
→ https://srof.scientiam.com.ar/mcp
→ Cloudflare Tunnel (transport only)
→ SROF MCP OAuth Resource Server
→ host policy / allowlists / receipts
→ governed OpenSSH
→ managed host
```

OAuth authorization:

```text
https://auth.scientiam.com.ar/realms/scientiam-srof
→ Keycloak 26.7.4
→ Founder password + TOTP
```

Cloudflare Access / Zero Trust is not used.

## OAuth contract

- MCP resource: `https://srof.scientiam.com.ar/mcp`
- issuer: `https://auth.scientiam.com.ar/realms/scientiam-srof`
- required scope: `srof:read`
- resource/audience validation: required
- PKCE S256: enabled
- CIMD: enabled
- RFC 9728 Protected Resource Metadata: enabled
- anonymous MCP access: denied with 401

## Current tool authority

Current MCP surface is read-only.

Remote inspection is governed by host registry capabilities and allowlists.

No arbitrary shell and no mutation tool is currently exposed.

## Invariants

- One SROF authority plane.
- One host registry.
- One receipt model.
- Multiple authorized MCP clients may use the same resource.
- No direct AI root.
- No public SSH.
- No public 8765.
- No DCP.
- No GitHub Actions transport.
- Cloudflare is transport, not identity authority.
- Keycloak is identity/authorization authority.
- Transport reachability does not imply host/tool authority.

## Chat/tool-exposure distinction

Remote SROF backend health and ChatGPT tool exposure are separate gates.

A ChatGPT runtime can use SROF only when that runtime exposes or registers the corresponding custom MCP/app binding.

Prompts cannot create a missing tool binding.

If the binding is absent:

```text
TOOLING_GAP — STRAN/SROF no está expuesto en este runtime.
```

The chat must not fall back to DCP or GitHub Actions.
