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

- hosts_list
- host_health
- service_status
- git_status
- docker_ps
- journal_tail

Mutation tools are added only after policy/readback tests exist.
