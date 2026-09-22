# SCIENTIAM Remote Operations Fabric (SROF)

**Priority:** P0  
**Product:** SPM-SCIENTIAM-REMOTE-OPERATIONS-FABRIC-001  
**Goal:** remove Desktop Commander Remote as a critical dependency by providing self-hosted, auditable remote operations for humans and AI workers.

## Delivery rule

A remote capability is not considered delivered until it has:

1. reachable runtime;
2. least-privilege authentication;
3. policy/authority check;
4. execution readback;
5. durable receipt;
6. human-visible control surface;
7. tested recovery/fallback path.

## Planes

- **Human Operations Plane:** MeshCentral first; RustDesk optional for richer GUI.
- **AI Operations Plane:** SCIENTIAM MCP gateway using OpenSSH/SCP/rsync and bounded filesystem roots.
- **Execution Plane:** versioned allowlisted operations only; generic shell disabled by default.
- **Governance Plane:** Control Registry + Slot Control Plane + receipts + publication gate.
- **Fallback Plane:** DCP remains non-critical fallback until exit criteria pass.

## Non-negotiables

- no SaaS quota may be the only path to administer SCIENTIAM;
- no password or private key in Git;
- no database-provided shell command;
- no direct AI root access;
- write operations require explicit authority;
- production mutations require verify/readback;
- external publication remains a separate authority gate.

## P0 sequence

1. MeshCentral self-hosted.
2. SSH hardening and host registry.
3. Read-only MCP operations.
4. Controlled write operations.
5. Slot Control Plane integration.
6. ThinkPad/server smoke tests.
7. DCP demotion to fallback.
