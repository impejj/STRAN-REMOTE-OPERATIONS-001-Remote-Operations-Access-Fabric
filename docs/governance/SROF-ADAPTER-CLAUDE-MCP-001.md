# CANON — Claude Remote MCP Adapter for SROF

**ID:** SROF-ADAPTER-CLAUDE-MCP-001
**Status:** CANDIDATE / IMMEDIATE VALIDATION
**Effective:** 2026-09-25

## Purpose

Provide a direct native-tool path from Claude to the existing SROF remote MCP endpoint without GitHub Actions or DCP.

## Architecture

```text
Claude
  -> Custom Connector (remote MCP)
  -> https://srof.scientiam.com.ar/mcp
  -> Keycloak OAuth / PKCE / MFA
  -> SROF
  -> governed OpenSSH
  -> PROFESYS-SCIENTIAM / THINKPAD-E470
```

## Product availability

Anthropic documents custom remote MCP connectors for Free, Pro, Max, Team and Enterprise. Free is limited to one custom connector.

## Registration

For individual Free/Pro/Max accounts:
1. Customize -> Connectors.
2. Add custom connector.
3. Name: SCIENTIAM SROF.
4. URL: https://srof.scientiam.com.ar/mcp
5. Complete OAuth when prompted.
6. Enable the connector in the conversation.

For Team/Enterprise, an Owner adds the custom connector at organization level and users authenticate individually.

## Acceptance test

Do not declare CLAUDE_SROF_BOUND until all gates pass:

```text
CONNECTOR_ADDED = PASS
OAUTH_DISCOVERY = PASS
FOUNDER_LOGIN = PASS
TOTP = PASS
TOOL_DISCOVERY = PASS
hosts_list = PASS
host_health(PROFESYS-SCIENTIAM) = PASS
host_health(THINKPAD-E470) = PASS
RECEIPT = PASS
```

## Expected initial tool surface

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

## Important caveat

This adapter removes GitHub Actions from the request path, but it is still dependent on Anthropic availability and usage limits.

It therefore MUST NOT replace the provider-independent SROF Relay / Local Console workstream.

## Transport priority

```text
1. Direct native MCP adapter when available (Claude today; other clients later)
2. SROF-GH-BRIDGE-001 as interoperable fallback
3. SROF Relay / Local Console as provider-independent break-glass path
```

Claude is an adapter. SROF remains the control plane.
