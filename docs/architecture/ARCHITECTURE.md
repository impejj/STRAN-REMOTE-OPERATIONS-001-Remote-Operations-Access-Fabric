# SROF Architecture

## Target

```
Human Browser
   |
   +--> MeshCentral -------------------------------+
                                                   |
AI clients -> MCP/HTTPS -> SROF Gateway -> Policy + Host Registry
                                                   |
                                                   +--> OpenSSH
                                                   |     +--> ThinkPad
                                                   |     +--> Server
                                                   |     +--> Workers
                                                   |
                                                   +--> SCP / rsync
                                                   +--> systemd / Docker / Git adapters
                                                   |
                                                   +--> Receipt Store / Control Registry
                                                   |
                                                   +--> Slot Control Plane
```

## Separation of concerns

### MeshCentral
Human emergency/interactive operations. It is not the AI control plane.

### SROF Gateway
Small, inspectable MCP service. It never owns host credentials in source control and never accepts arbitrary shell text from database queues.

### OpenSSH
Transport and identity substrate. Keys and certificates remain outside Git.

### Slot Control Plane
Chooses logical slot and physical execution channel. SROF performs the authorized remote operation and returns evidence.

## Tool surface v0.1

Read-only:
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

Controlled mutations:
- `service_restart`
- `file_put`
- `file_move`
- `git_fetch`
- `git_checkout_allowlisted`
- `docker_restart_allowlisted`

Disabled by default:
- arbitrary shell;
- arbitrary sudo;
- deleting outside approved roots;
- publishing externally;
- credential manipulation.

## Receipts

Every operation returns:
- request_id;
- actor;
- host_id;
- tool;
- authority decision;
- started_at / finished_at;
- exit code;
- bounded stdout/stderr;
- verification result;
- evidence hash/reference.

## Networking

P0 should work over LAN first. WAN exposure is a separate hardening step and must use an authenticated tunnel/reverse proxy with MFA; never expose raw SSH or MeshCentral broadly without CISO review.
