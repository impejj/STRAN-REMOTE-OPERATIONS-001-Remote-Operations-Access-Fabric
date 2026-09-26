# scientiam-remote-ops-gateway

P0 scaffold for the AI Operations Plane of SROF.

## Design

The gateway translates high-level operations into OpenSSH calls. It does **not** accept arbitrary shell strings from queues or databases.

The initial implementation intentionally exposes a small read-only core plus explicitly allowlisted mutation helpers.

## Environment

- `SROF_HOSTS_FILE` — JSON host registry outside source control.
- `SROF_RECEIPT_DIR` — receipt directory.
- standard `~/.ssh/config` — transport configuration.
- secrets/keys remain outside Git.

## Local development

```bash
python -m venv .venv
. .venv/bin/activate
pip install -e '.[dev]'
pytest
python -m srof_gateway.server
```

## P0 tools

Core host/runtime tools:

- hosts_list
- host_health
- fs_list / fs_read / fs_find
- process_list
- service_status
- docker_ps / docker_logs
- git_status / git_diff
- journal_tail
- network_listeners

Portable-worker bridge (candidate):

- worker_list
- worker_health
- worker_capabilities
- worker_read_job

`worker_read_job` can target only an allowlisted READ worker and only the
READ operation allowlist. DEV is intentionally visible through health and
capabilities but cannot execute through the A1 bridge.

Worker bearer tokens are read from protected files on the target host; they
are not MCP arguments and are not embedded as literal secrets in SSH argv.

See `docs/PORTABLE-WORKER-RUNTIME-BRIDGE.md`.

Mutation tools are added only after policy/readback tests exist.
