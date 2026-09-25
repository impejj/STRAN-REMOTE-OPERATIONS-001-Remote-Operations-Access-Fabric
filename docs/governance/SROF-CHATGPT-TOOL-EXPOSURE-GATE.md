# SROF-CHATGPT-TOOL-EXPOSURE-GATE

**State:** BACKEND_READY / RUNTIME_BINDING_REQUIRED

## What is already closed

- remote endpoint: `https://srof.scientiam.com.ar/mcp`
- Cloudflare dedicated tunnel: PASS
- native OAuth Resource Server: PASS
- Keycloak issuer: PASS
- PKCE S256: PASS
- CIMD: PASS
- RFC 9728 metadata: PASS
- anonymous access denied: PASS
- Founder password + TOTP: PASS
- actor-bound receipt model: implemented
- DCP: not used
- GitHub Actions transport: not used

## Remaining gate per ChatGPT runtime/workspace

A ChatGPT runtime is LIVE for SROF only after:

1. The runtime/workspace supports a custom remote MCP/app connection.
2. `SCIENTIAM SROF` is registered against:
   `https://srof.scientiam.com.ar/mcp`
3. OAuth discovery completes through the SROF RFC 9728 metadata.
4. Founder login + TOTP completes.
5. Tool scan/discovery returns the SROF tool surface.
6. `hosts_list` succeeds.
7. `host_health` succeeds for an authorized host.
8. The resulting SROF receipt contains OAuth actor/client/scope data.
9. No DCP call occurs.
10. No GitHub Actions remote transport occurs.

## Mandatory fallback behavior

If a chat/runtime does not expose the SROF MCP/app:

```text
TOOLING_GAP — STRAN/SROF no está expuesto en este runtime.
```

Do not:

- repeat prompts hoping the tool appears;
- tell the model to use raw SSH without a SROF binding;
- use DCP;
- use GitHub Actions as a bridge;
- expose additional ports to bypass the product gate.

## Important distinction

`BACKEND_READY` does not mean every ChatGPT chat can automatically invoke SROF.

Tool availability is a product/runtime binding property and must be verified in each environment.
