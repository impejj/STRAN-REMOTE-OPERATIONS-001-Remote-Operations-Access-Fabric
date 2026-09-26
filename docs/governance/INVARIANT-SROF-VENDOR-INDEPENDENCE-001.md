# INVARIANT-SROF-VENDOR-INDEPENDENCE-001

**Status:** ACTIVE / P0 / CANONICAL  
**Authority:** STRAN-REMOTE-OPERATIONS-001  
**Effective date:** 2026-09-26

## Rule

No critical Remote Operations capability may depend on:

- ChatGPT Plus or any other ChatGPT subscription tier;
- Desktop Commander / DCP;
- GitHub Actions as remote transport;
- a specific model provider;
- a specific conversational UI;
- a quota-bound third-party remote-control product.

SROF must remain operational when any one of those surfaces is unavailable.

## Architectural consequence

SROF is the execution fabric. AI products and human interfaces are consumers.

Canonical dependency direction:

```text
Human operator / AI client / automation
        ↓
optional adapter or control surface
        ↓
SROF authority + policy + receipts
        ↓
governed transport
        ↓
SERVER / ThinkPad / Workers
```

A consumer may disappear without disabling the fabric.

## ChatGPT plan boundary

As verified against OpenAI documentation on 2026-09-26:

- ChatGPT Plus is not a supported dependency for full custom MCP execution.
- Full MCP in ChatGPT, including write/modify actions, is available to Business and Enterprise/Edu; Pro has a narrower read/fetch developer-mode path.
- Therefore ChatGPT plan capabilities are treated as an optional product binding, never as the SROF execution substrate.

## OpenAI integration

OpenAI integration may use:

1. Responses API with a reachable remote MCP server via `server_url`.
2. Responses API with a private/local MCP server via Secure MCP Tunnel and `tunnel_id`.
3. A ChatGPT custom MCP/app binding only when the target workspace/plan actually exposes that capability.

OpenAI API credentials, billing and tunnel permissions are separate from a ChatGPT Plus subscription.

## Failure behavior

If ChatGPT does not expose the SROF binding, the correct state is:

```text
TOOLING_GAP — STRAN/SROF no está expuesto en este runtime.
```

That product limitation must not affect:

- human access through the Human Operations Plane;
- SSH-based managed access;
- local or self-hosted automation;
- SROF host registry and policy enforcement;
- receipt generation;
- other authorized MCP/API clients.

## Design test

A release cannot be considered production-ready if disabling ChatGPT access, OpenAI API access, or any single external control product prevents authorized local remote operations.

## Source references

- OpenAI Help Center: Developer mode and MCP apps in ChatGPT.
- OpenAI API docs: MCP servers.
- OpenAI API docs: Secure MCP Tunnel.

These sources define adapter capability, not SROF authority.
