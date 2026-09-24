# ChatGPT ↔ SROF Exposure Runbook

**Status:** PREPARED / PRODUCT-ACCESS-GATED  
**Transport:** OpenAI Secure MCP Tunnel → local SROF MCP Gateway → governed OpenSSH  
**Forbidden fallbacks:** DCP; GitHub Actions as remote transport

## Why this exists

A prompt cannot expose a tool to a ChatGPT runtime. The SROF backend can be healthy while a given ChatGPT chat still lacks any SROF tool. The missing layer is product registration/exposure.

The canonical private path is:

```text
ChatGPT
  → OpenAI Secure MCP Tunnel
  → SROF MCP Gateway (127.0.0.1:8765/mcp)
  → host policy / receipts
  → governed OpenSSH
  → ThinkPad / SERVER
```

The SROF MCP gateway remains private. No inbound firewall rule is required.

## Current SROF endpoint

- service: `scientiam-remote-ops-gateway.service`
- transport: streamable HTTP
- URL from tunnel-client host: `http://127.0.0.1:8765/mcp`
- listener: loopback only
- receipts: `/var/lib/scientiam/remote-ops/receipts`

## OpenAI product gate

Native ChatGPT custom MCP availability is plan/workspace dependent.

For write/modify actions, use a ChatGPT workspace that supports full custom MCP. If the account/workspace does not expose developer mode/custom MCP, prompts cannot bypass that product gate.

## OpenAI-side one-time setup

1. In the OpenAI Platform organization, create a Secure MCP Tunnel.
2. Associate the tunnel with the target ChatGPT workspace.
3. Grant the runtime identity Tunnels Read + Use.
4. Create a runtime API key for tunnel-client. Never commit it.
5. Download/install the current official `tunnel-client` release.
6. Initialize the profile:

```bash
export CONTROL_PLANE_API_KEY='...'

tunnel-client init \
  --profile srof-chatgpt \
  --tunnel-id 'tunnel_...' \
  --mcp-server-url 'http://127.0.0.1:8765/mcp'

tunnel-client doctor --profile srof-chatgpt --explain
```

7. Keep `tunnel-client run --profile srof-chatgpt` healthy.
8. In ChatGPT Developer Mode / Apps, create a custom MCP app:
   - Name: `SCIENTIAM SROF`
   - Connection: Tunnel
   - Tunnel: the SROF tunnel
9. Scan tools and verify the discovered SROF tool set.
10. Publish/enable for the intended workspace/users.

## Expected discovered tools

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

## Server-side service

Install:

```bash
sudo install -m 0644 deploy/openai-tunnel/openai-srof-tunnel.service \
  /etc/systemd/system/openai-srof-tunnel.service

sudo install -d -m 0750 -o root -g scientiam-remoteops \
  /etc/scientiam/remote-ops

sudo install -m 0640 -o root -g scientiam-remoteops \
  deploy/openai-tunnel/openai-tunnel.env.example \
  /etc/scientiam/remote-ops/openai-tunnel.env
```

Edit only the real env file and insert the runtime API key. Do not paste the key into chat or Git.

After `tunnel-client init` and a successful doctor:

```bash
sudo systemctl daemon-reload
sudo systemctl enable --now openai-srof-tunnel.service
sudo systemctl status openai-srof-tunnel.service --no-pager
```

## Acceptance gate

The connection is not LIVE until all are true:

```text
SROF_GATEWAY_LOCAL = PASS
TUNNEL_CLIENT_DOCTOR = PASS
TUNNEL_SERVICE = active
CHATGPT_TOOL_SCAN = PASS
hosts_list = PASS
host_health(PROFESYS-SCIENTIAM) = PASS
host_health(THINKPAD-E470) = PASS
RECEIPT_READBACK = PASS
DCP_USED = NO
GITHUB_ACTIONS_TRANSPORT = NO
```

## Runtime rule for every chat

If `SCIENTIAM SROF` is available, select/@mention it for the message that needs machine access.

If it is not available in that chat/runtime:

```text
TOOLING_GAP — STRAN/SROF no está expuesto en este runtime.
```

Do not use DCP or GitHub Actions as fallback.
