# SROF-GAP-BRIDGE-001 — Temporary Governed Remote Command Bus

**Status:** PREPARED / NOT LIVE  
**Purpose:** temporary continuity while direct ChatGPT custom-MCP exposure is unavailable.

## Transport

```text
ChatGPT with connected Google Drive
→ governed REQUESTS row in a fixed Google Sheet
→ server-side SROF gap bridge
→ existing SROF high-level operation
→ governed OpenSSH
→ SERVER / THINKPAD
→ SROF receipt
→ RECEIPTS sheet + local receipt
```

This is **not** arbitrary shell and is **not** GitHub Actions transport.

## Current sheet

`SROF-GAP-BRIDGE-001 — Governed Remote Command Bus`

Spreadsheet ID:

`1W-mH511i-TcJLN8wSYsAH8MrhKYNKXu2nQlV1X9XrHo`

Folder:

`SCIENTIAM_CONNECT`

Tabs:
- REQUESTS
- RECEIPTS
- CONTROL

## Initial authority

The first cut is deliberately **READ_ONLY/T0**.

Allowed operations:
- hosts_list
- host_health
- fs_list
- fs_read
- fs_find
- process_list
- service_status
- docker_ps
- docker_logs
- git_status
- git_diff
- journal_tail
- network_listeners

Anything else fails closed.

## Request contract

One REQUESTS row:

- request_id: unique immutable ID
- created_at: ISO timestamp
- actor: chat/AIPS identity
- target_host: SROF host ID, empty only for hosts_list
- operation: allowlisted high-level SROF operation
- args_json: JSON object only
- risk_class: READ_ONLY or T0
- status: PENDING

The server changes status through CLAIMED to DONE / FAILED / DENIED.

## Execution rules

- One fixed spreadsheet ID from environment.
- One fixed Google credential file local to server.
- No private key in Drive/Git/chat.
- No caller-supplied shell command.
- All host/path/service/repository authority still comes from the SROF host registry.
- Local SROF receipts remain mandatory.
- Result is copied to RECEIPTS for cross-chat readback.

## Bootstrap

On `profesys-scientiam`:

1. Ensure the service-account credential exists locally.
2. Share the bridge spreadsheet with that service account as Editor.
3. Pull the canonical SROF repository through normal SCM.
4. Install bridge dependency group:
   ```bash
   /opt/scientiam/remote-ops-gateway/.venv/bin/pip install -e '/path/to/repo/gateway[gap-bridge]'
   ```
5. Install the env file and systemd unit.
6. Enable/start `scientiam-srof-gap-bridge.service`.
7. Enqueue a READ_ONLY host_health request.
8. Require REQUESTS=DONE + RECEIPTS row + local receipt before declaring LIVE.

## Retirement

When ChatGPT ↔ Cloudflare/Custom MCP is stable for all required chats, disable the bridge:

```bash
sudo systemctl disable --now scientiam-srof-gap-bridge.service
```

The spreadsheet and receipts remain as migration evidence.
