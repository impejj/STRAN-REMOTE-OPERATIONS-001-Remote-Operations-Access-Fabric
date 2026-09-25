# CANON — SROF GitHub Compatibility Bridge

**ID:** SROF-GH-BRIDGE-001
**Status:** ACTIVE / TEMPORARY COMPATIBILITY LAYER
**Effective:** 2026-09-24
**Authority:** STRAN-REMOTE-OPERATIONS-001

## Decision

Native SCIENTIAM SROF MCP remains the preferred and canonical ChatGPT machine-access path.

When the current ChatGPT product/runtime does not expose the SROF MCP binding, the following temporary compatibility path is authorized:

```text
ChatGPT
  -> GitHub connector
  -> issue in impejj/profesys-scientiam
  -> SROF Chat Compatibility Bridge workflow
  -> self-hosted runner on PROFESYS-SCIENTIAM
  -> bounded read-only operation
  -> dedicated governed SSH for THINKPAD-E470 when needed
  -> GitHub issue comment + local receipt
```

## Security boundary

- DCP remains retired.
- Arbitrary shell is denied.
- Only requests created by GitHub user `impejj` are accepted.
- Workflow must execute on host `profesys-scientiam`.
- Operations are explicit and allowlisted.
- Inputs are parsed as JSON and validated.
- Filesystem paths are bounded to declared roots.
- GitHub Actions is not a general remote shell.
- Mutation operations are not authorized by this v1 bridge.
- Every request produces a bridge receipt.

## v1 operation allowlist

- `hosts_list`
- `host_health`
- `service_status`
- `git_status`
- `fs_list`
- `fs_read`

Host OS permissions and policy restrictions remain effective. A bridge request may be denied even if the operation name is allowlisted.

## Request contract

Repository:
`impejj/profesys-scientiam`

Issue title prefix:
`[SROF-BRIDGE]`

Issue body:

```json
{
  "schema": "SROF_GH_BRIDGE_REQUEST_V1",
  "operation": "host_health",
  "host_id": "THINKPAD-E470",
  "args": {}
}
```

## Result contract

The workflow comments the result back on the same issue.

Receipt schema:
`SROF_GH_BRIDGE_RECEIPT_V1`

Receipt includes:
- GitHub actor;
- workflow run ID;
- issue number;
- request;
- exit code;
- bounded stdout/stderr;
- explicit DCP_USED=NO;
- explicit arbitrary-shell denial.

## Runtime selection rule

1. If native `SCIENTIAM SROF` MCP is exposed, use it.
2. Otherwise, if the GitHub connector is available, use SROF-GH-BRIDGE-001 for allowlisted read-only operations.
3. If neither is available, return TOOLING_GAP.

GitHub bridge authorization is temporary and removable once native SROF custom MCP is available in the active ChatGPT product/runtime.
