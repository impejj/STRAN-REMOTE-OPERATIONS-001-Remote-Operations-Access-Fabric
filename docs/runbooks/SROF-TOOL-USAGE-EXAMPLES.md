# SROF Tool Usage Examples

These examples describe chat behavior, not an alternate transport.

## Host discovery

User: "¿Cómo están las máquinas?"

1. Call `hosts_list()`.
2. For relevant authorized hosts, call `host_health(host_id)`.
3. Report receipt IDs with the result.

## Repository inspection

User: "Revisá el repo X en la ThinkPad."

1. Confirm SROF binding exists.
2. Use `hosts_list()` if the host ID/capability is not already known in the current runtime.
3. Call `git_status(host_id, repository)`.
4. Call `git_diff(...)` only if useful.
5. Do not mutate the repository because current SROF MCP has no mutation tool.

## Service diagnosis

User: "¿Está vivo el servicio Y?"

1. `service_status(host_id, service)`.
2. If needed, `journal_tail(host_id, service)`.
3. If the service is down, report it.
4. Do not invent `service_restart`; current SROF surface is read-only.

## Files

User: "Buscá el archivo/configuración Z."

Use only allowed roots through `fs_find`, `fs_list`, `fs_read`.

If policy rejects the path, report the policy denial. Do not bypass the allowlist.

## Runtime without SROF binding

Return exactly:

```text
TOOLING_GAP — STRAN/SROF no está expuesto en este runtime.
```

Do not propose DCP or GitHub Actions as fallback.
