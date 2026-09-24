# SROF Native OAuth — no-card architecture

**Status:** PREPARED / LOCAL-FIRST / NOT PUBLIC

## Decision

Cloudflare Tunnel remains the HTTPS transport, but Cloudflare Access / Zero Trust
is not used. Authentication and authorization are owned by PROFESYS.

```text
ChatGPT / MCP client
  -> https://srof.scientiam.com.ar/mcp
  -> Cloudflare Tunnel (transport only)
  -> SROF Resource Server
       -> OAuth bearer validation
       -> RFC 9728 Protected Resource Metadata
       -> exact issuer / audience / scope validation
       -> governed SROF host policy
       -> audited receipt
  -> OpenSSH
  -> SERVER / THINKPAD

OAuth authorization
  -> https://auth.scientiam.com.ar
  -> same dedicated Cloudflare Tunnel
  -> Keycloak 26.7.4
  -> loopback 127.0.0.1:8096
```

## Identity and standards

Authorization Server: Keycloak 26.7.4.

SROF is an OAuth Resource Server only. It never issues bearer tokens.

Required token properties:
- signature valid through Keycloak JWKS;
- issuer exactly `https://auth.scientiam.com.ar/realms/scientiam-srof`;
- audience exactly includes `https://srof.scientiam.com.ar/mcp`;
- unexpired token;
- subject present;
- scope `srof:read`.

MCP SDK authorization is configured with:
- `TokenVerifier`;
- `AuthSettings.issuer_url`;
- `AuthSettings.resource_server_url`;
- `required_scopes=["srof:read"]`;
- `validate_token_resource=True`.

The SDK supplies the RFC 9728 metadata endpoint at:

`/.well-known/oauth-protected-resource/mcp`

## Keycloak / MCP compatibility

Keycloak currently does not natively bind MCP's RFC 8707 `resource` parameter.
The official Keycloak MCP guidance recommends using an optional OAuth scope with
an Audience mapper as the binding workaround.

For SROF:
- optional scope: `srof:read`;
- custom audience: `https://srof.scientiam.com.ar/mcp`;
- SROF verifies that audience exactly.

## ChatGPT client registration

CIMD is enabled in Keycloak.

Only HTTPS client IDs hosted on `chatgpt.com` match the SROF CIMD policy.
The profile accepts metadata URLs only on:
- `chatgpt.com`;
- `persistent.oaistatic.com` (official ChatGPT logo URI).

The profile requires a confidential client. ChatGPT's current CIMD metadata
uses `private_key_jwt` and publishes a JWKS URI.

## Founder authentication

The Keycloak bootstrap administrator is machine-generated and stored only in
the root-controlled local env file.

The Founder gets a separate user account:
- password entered through a hidden prompt;
- TOTP enrollment required on first login;
- brute-force protection enabled at realm level.

## Audit

SROF receipts persist:
- request ID;
- target host;
- operation;
- exit status;
- bounded stdout/stderr;
- command digest;
- OAuth subject;
- OAuth client ID;
- scopes.

Bearer tokens and full claims are never written to receipts.

## Network invariants

Before public cutover:
- Keycloak app: `127.0.0.1:8096`;
- Keycloak health: `127.0.0.1:9006`;
- SROF: `127.0.0.1:8765`;
- PostgreSQL: Docker-internal only;
- no public SSH;
- no public TCP/8765;
- existing `gastos-mama` tunnel untouched.

## Activation order

1. Validate committed assets.
2. Run read-only preflight.
3. Deploy Keycloak locally.
4. Read back realm scope, audience, CIMD profile and policy.
5. Create Founder user and require TOTP.
6. Upgrade SROF to MCP SDK 1.30.x and activate OAuth locally.
7. Require anonymous `/mcp` = 401.
8. Require RFC 9728 metadata = expected issuer/resource/scope.
9. Only then publish the OAuth and MCP routes through the dedicated SROF tunnel.
10. Complete a real ChatGPT OAuth flow and require an actor-bound SROF receipt.

## Rollback

If local SROF OAuth activation fails, the activation helper moves the OAuth env
out of the active path and restarts the gateway in its prior local mode.

Cloudflare routes are not created by the local activation helpers.
