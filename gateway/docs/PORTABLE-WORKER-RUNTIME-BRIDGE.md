# SROF Portable Worker Runtime Bridge — Candidate

Status: **CANDIDATE / PROVISIONAL_REVERSIBLE / NO CANON PROMOTION**

Parent: `STRAN-REMOTE-OPERATIONS-001`

## Purpose

Bind the already-built SROF portable Docker workers to the canonical SROF MCP gateway without adding arbitrary shell, embedding worker secrets in ChatGPT requests, or granting DEV/OPS authority through a READ scope.

## Current allowlist

- `SROF-WORKER-READ-001` — role READ — loopback port 8781.
- `SROF-WORKER-DEV-001` — role DEV — loopback port 8782.

The inventory is an allowlist, not runtime truth. Call `worker_health` and `worker_capabilities` for live evidence.

## MCP tools added

- `worker_list(host_id)`
- `worker_health(host_id, worker_id)`
- `worker_capabilities(host_id, worker_id)`
- `worker_read_job(host_id, operation, args, worker_id=...)`

`worker_read_job` only accepts a READ-role worker and the READ worker's fixed operation allowlist:

- `fs_list`
- `fs_read`
- `fs_find`
- `git_status`
- `git_diff`

There is deliberately **no DEV execution tool in this bridge**. DEV stays behind its existing `PROFILE-DEV-WORKTREE / A2` authority gate.

## Secret boundary

ChatGPT/MCP never supplies the worker bearer token.

The worker token is stored locally on each authorized host:

```text
/etc/scientiam/srof-workers/read.token
/etc/scientiam/srof-workers/dev.token
```

The SROF SSH identity reads the token file on the target host and injects it into the loopback HTTP request. The token value is not part of:

- MCP arguments;
- remote structured argv;
- command digest input as a literal secret;
- SROF gateway response;
- Git.

Recommended permissions are owned by the dedicated remote-ops identity and mode `0600`.

## Runtime path

```text
ChatGPT native SROF tool
 -> canonical SROF MCP gateway
 -> host policy / DOCKER capability gate
 -> structured OpenSSH argv
 -> target host
 -> 127.0.0.1:8781
 -> SROF-WORKER-READ-001
 -> typed READ operation
 -> worker receipt
 -> SROF SSH receipt
 -> MCP readback
```

No GitHub Actions or DCP transport is introduced by this bridge.

## Fail-closed behavior

- unknown worker ID -> denied;
- host without DOCKER capability -> denied;
- READ bridge targeting DEV worker -> denied;
- non-allowlisted READ operation -> denied;
- missing local token file -> worker request fails;
- worker endpoint unavailable -> request fails;
- worker HTTP error -> request fails and SROF receipt captures bounded evidence.

## Host readiness requirements

A host is eligible only when all of the following are independently true:

1. its SROF host registry state is executable;
2. `DOCKER` is an evidenced capability;
3. the selected worker container is running on the expected loopback port;
4. the local token file exists with least privilege;
5. worker health returns HEALTHY;
6. worker capabilities match the requested operation.

Do not add DOCKER to a host registry solely to satisfy this bridge. Verify it first.

## Portability proof

The workers are not promoted to portable production capacity until the same image and contract pass on at least two authorized hosts.

Initial target pair:

- `PROFESYS-SCIENTIAM`
- `THINKPAD-E470`

This document does not claim that second-host proof has occurred.
