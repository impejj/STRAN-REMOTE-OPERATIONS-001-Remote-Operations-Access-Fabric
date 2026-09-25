# SROF GitHub Bridge — Chat Bootstrap

Use when native SCIENTIAM SROF MCP tools are not exposed in the current ChatGPT runtime.

Rules:
- Prefer native SCIENTIAM SROF when available.
- Otherwise use repository `impejj/profesys-scientiam`.
- Create a GitHub issue whose title begins `[SROF-BRIDGE]`.
- Body must be `SROF_GH_BRIDGE_REQUEST_V1` JSON.
- Fetch the same issue comments until `github-actions[bot]` posts the bridge receipt.
- Never place arbitrary shell in the request.
- Never use DCP.
- Do not use any workflow other than the canonical `SROF Chat Compatibility Bridge` for this fallback.

Example:

```json
{
  "schema": "SROF_GH_BRIDGE_REQUEST_V1",
  "operation": "host_health",
  "host_id": "PROFESYS-SCIENTIAM",
  "args": {}
}
```

Current v1 operations:
`hosts_list`, `host_health`, `service_status`, `git_status`, `fs_list`, `fs_read`.

If neither native SROF nor GitHub connector is available:

`TOOLING_GAP — no hay transporte SROF ejecutable en este runtime.`
