# SROF-CHATGPT-TOOL-EXPOSURE-GATE

**State:** BLOCKED_BY_PRODUCT_EXPOSURE until ChatGPT discovers the private MCP through an approved connection.

## Problem statement

SROF transport and the local MCP gateway are separate from ChatGPT tool exposure. Chat-to-chat inconsistency is expected when some runtimes do not receive the SROF app/tool.

Prompts are not a transport and cannot dynamically install or expose MCP tools.

## Required closure

1. SROF gateway healthy.
2. OpenAI Secure MCP Tunnel associated with the target ChatGPT workspace.
3. tunnel-client healthy and persistent.
4. ChatGPT custom app `SCIENTIAM SROF` created and tool scan PASS.
5. App enabled/published for the intended users.
6. New chat test discovers `hosts_list` and `host_health`.
7. Both initial hosts read back successfully.
8. Receipts prove the calls were executed through SROF.
9. No DCP call.
10. No GitHub Actions transport.

## Non-solutions

- repeating a prompt;
- telling a chat to “use SSH” without an exposed tool;
- DCP fallback;
- GitHub Actions/self-hosted runner as remote bridge;
- public exposure of the private SROF gateway merely to bypass the product gate.
