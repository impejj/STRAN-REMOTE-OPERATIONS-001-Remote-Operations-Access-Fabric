# STRAN-REMOTE-OPERATIONS-001 — Remote Operations & Access Fabric

## Status

ACTIVE · P0 · TRANSVERSAL

## Role

Govern the remote operations capability used by SCIENTIAM/PROFESYS across human operators, AI agents, servers, workstations and future workers.

This STRAN owns the capability boundary. It does not grant unrestricted infrastructure authority.

## Implementation

The current implementation is **SROF — SCIENTIAM Remote Operations Fabric**.

SROF is an implementation of this STRAN, not a new ontological family.

## Planes

### Human Operations Plane
Interactive administration through self-hosted remote-management tooling. Current P0 implementation: MeshCentral.

### AI Operations Plane
Governed MCP/OpenSSH operations with:
- explicit host registry;
- capability and path allowlists;
- least-privilege identities;
- bounded tool surface;
- post-condition verification;
- durable receipts.

## Authority boundaries

Allowed by policy only:
- host health and inventory;
- bounded filesystem inspection;
- process inspection;
- allowlisted systemd/Docker/Git/log operations;
- controlled file transfer.

Not implicitly allowed:
- arbitrary root shell;
- arbitrary sudo;
- credential changes;
- external publication;
- firewall/WAN exposure changes;
- secret access;
- destructive filesystem operations.

## Consumers

Potential consumers include:
- SCIENTIAM Control Plane;
- SEF workers;
- governed AIPS execution paths;
- human operators;
- incident/recovery workflows.

Consumers do not become owners of this STRAN.

## Canonical source

This repository is the technical source of truth for the STRAN implementation.

The original implementation in `impejj/profesys-scientiam` is historical origin and integration context only.

## P0 exit criterion

DCP can be demoted from critical dependency only when a deliberate DCP-outage drill proves that self-hosted paths provide terminal, transfer, health, logs, service control and evidence collection without DCP.
