# CANON — SROF Remote MCP Access

**Status:** CANDIDATE / PREPARED FOR FOUNDER AUTHORIZATION

## Decision target

Use a neutral HTTPS access plane for SROF so multiple authorized MCP clients can reach the same governed remote-operations fabric.

Preferred neutral path:

```text
Authorized MCP client
→ Cloudflare Access
→ Cloudflare Tunnel
→ SROF MCP Gateway
→ governed OpenSSH
→ managed host
```

OpenAI Secure MCP Tunnel may remain an OpenAI-specific integration option, but it is not the only transport architecture.

## Invariants

- One SROF authority plane.
- One host registry.
- One receipt model.
- Multiple authorized clients.
- No direct AI root.
- No arbitrary shell by default.
- No public SSH.
- No DCP.
- No GitHub Actions transport.
- Access transport does not imply mutation authority.

## Tool-exposure distinction

Remote connectivity and ChatGPT tool exposure are separate gates.

Cloudflare can make the private MCP securely reachable. A ChatGPT runtime can use it only if that runtime/account/workspace supports adding or invoking the corresponding MCP/plugin connection.

Prompts cannot create a missing tool binding.
