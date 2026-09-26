# SROF Architecture

## Target

```
Human Browser
   |
   +--> MeshCentral -------------------------------+
                                                   |
AI clients / automations -> adapter/MCP/API -> SROF Gateway -> Policy + Host Registry
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

## Dependency rule

SROF is client-neutral and vendor-neutral. ChatGPT, OpenAI API, Claude, local agents, CLIs and future clients are adapters/consumers. None is required for core Remote Operations.

Critical host access, policy evaluation and evidence generation must remain available if any single external AI/control provider is unavailable.

## Separation of concerns

### MeshCentral
Human emergency/interactive operations. It is not the AI control plane.

### SROF Gateway
Small, inspectable MCP service. It never owns host credentials in source control and never accepts arbitrary shell text from database queues. It exposes a stable contract to multiple authorized clients rather than binding the fabric to one AI product.

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

P0 must work independently on the managed network first. WAN access is a separate hardened transport concern and must never turn a third-party control product into a critical dependency.

Authorized adapter options may include the existing public HTTPS SROF endpoint or a private MCP connection through a secure outbound tunnel. Raw SSH or MeshCentral must never be broadly exposed without security review.
