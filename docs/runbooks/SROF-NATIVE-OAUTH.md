# SROF Native OAuth — canonical production architecture

**Status:** ACTIVE / REMOTE-OAUTH-READY  
**Decision:** Cloudflare Tunnel is transport only. PROFESYS owns authentication and authorization through Keycloak.

## Architecture

```text
Authorized MCP client
  -> https://srof.scientiam.com.ar/mcp
  -> Cloudflare Tunnel
  -> SROF OAuth Resource Server
       -> JWT verification
       -> RFC 9728 metadata
       -> issuer/audience/expiry/subject/scope validation
       -> host policy
       -> actor-bound receipt
  -> governed OpenSSH
  -> SERVER / THINKPAD

OAuth authorization
  -> https://auth.scientiam.com.ar
  -> auth-edge allowlist
  -> Keycloak 26.7.4
```

Cloudflare Access / Zero Trust is not used.

## Identity contract

- issuer: `https://auth.scientiam.com.ar/realms/scientiam-srof`
- resource/audience: `https://srof.scientiam.com.ar/mcp`
- required scope: `srof:read`
- algorithms: RS256
- PKCE S256: enabled
- CIMD: enabled
- Founder MFA: password + TOTP

SROF is an OAuth Resource Server only and never issues bearer tokens.

## Current infrastructure

- SROF local listener: `127.0.0.1:8765`
- Keycloak direct/local: `127.0.0.1:8096`
- Keycloak health: `127.0.0.1:9006`
- public auth edge: `127.0.0.1:8097`
- dedicated Cloudflare tunnel publishes:
  - `srof.scientiam.com.ar -> http://127.0.0.1:8765`
  - `auth.scientiam.com.ar -> http://127.0.0.1:8097`

The auth-edge blocks Keycloak admin, master realm, other realms and root from the public surface.

Keycloak trusts only loopback plus the dynamically discovered Docker subnet containing auth-edge.

## MCP compatibility

Keycloak 26.7.x does not natively bind MCP RFC 8707 resource indicators in the way the MCP server requires.

Canonical workaround:
- optional OAuth scope: `srof:read`
- Audience mapper injects:
  `https://srof.scientiam.com.ar/mcp`
- SROF validates that audience exactly.

## ChatGPT CIMD policy

CIMD is enabled.

Client-ID URI condition:
- scheme: `["https"]`
- trusted client-id domain: `chatgpt.com`

Allowed metadata domains in the CIMD profile:
- `chatgpt.com`
- `persistent.oaistatic.com`

Confidential client is required.

## Human authentication

Founder:
- dedicated realm user;
- permanent password;
- TOTP enrollment completed;
- no pending required action.

## Audit

SROF receipts persist:

- request ID;
- host ID;
- operation;
- timestamps;
- exit code;
- bounded stdout/stderr;
- command digest;
- OAuth subject;
- OAuth client ID;
- scopes.

Bearer token and full claims are not persisted.

## Network/security invariants

- no public SSH;
- no public TCP/8765;
- Cloudflare Tunnel outbound-only;
- Keycloak admin local-only;
- SROF listener loopback-only;
- PostgreSQL Docker-internal;
- no Cloudflare Access;
- no DCP;
- no GitHub Actions transport;
- no arbitrary shell from MCP prompts.

## Current readiness

```text
CLOUDFLARE_DEDICATED_TUNNEL = PASS
SROF_REMOTE_ROUTE = PASS
AUTH_REMOTE_ROUTE = PASS
OIDC_DISCOVERY = PASS
PKCE_S256 = PASS
CIMD = PASS
ANONYMOUS_MCP_DENY = PASS
RFC9728_METADATA = PASS
FOUNDER_TOTP = PASS
SROF_READONLY_TOOL_SURFACE = IMPLEMENTED

CHATGPT_BINDING = PER-RUNTIME / PRODUCT GATE
MUTATION_TOOLS = NOT EXPOSED
```
