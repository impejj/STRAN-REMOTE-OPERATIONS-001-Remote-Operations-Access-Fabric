# SROF isolated DEV worker POC

Status: POC / CANDIDATE / NO CANON MUTATION

Purpose: prove that DEV execution can run in an isolated ephemeral workspace without touching the human working tree.

## Security model

- source repository is mounted read-only at `/src`;
- worker copies source to an ephemeral container workspace;
- `.git`, `.secrets`, `.ssh`, `keys` and `secrets` are excluded from the copy;
- only `pytest_selected` is accepted;
- test paths are restricted to known SCIENTIAM test roots;
- no arbitrary shell;
- no Docker socket;
- no host root mount;
- no sudo;
- no push/merge/deploy;
- output is written to `/out/result.json`.

## Existing certification mapping

This POC targets `PROFILE-DEV-WORKTREE` from `STD-SC-WORKER-CERTIFICATION-001`.

It is not production-certified merely because the container executes successfully.

## Example

```bash
docker run --rm \
  --read-only \
  --tmpfs /tmp:rw,noexec,nosuid,size=1g \
  --cap-drop=ALL \
  --security-opt=no-new-privileges \
  -v /path/to/clean/scientiam:/src:ro \
  -v /tmp/srof-worker-output:/out \
  srof-worker-dev-poc:latest <<'JSON'
{
  "schema": "srof.worker.job.v0.1",
  "request_id": "probe-001",
  "operation": "pytest_selected",
  "tests": [
    "services/agent-control-plane/tests/test_work_generation_engine.py"
  ]
}
JSON
```

The source mount MUST be a clean execution snapshot/worktree. The human ThinkPad checkout is explicitly not an eligible DEV source.
