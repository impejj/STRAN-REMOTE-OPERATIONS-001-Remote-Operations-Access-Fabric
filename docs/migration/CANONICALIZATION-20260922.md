# Canonicalization — 2026-09-22

## Decision

Remote Operations becomes a dedicated transversal capability under:

`STRAN-REMOTE-OPERATIONS-001 — Remote Operations & Access Fabric`

Implementation codename:

`SROF — SCIENTIAM Remote Operations Fabric`

## Origin

Initial work was implemented inside `impejj/profesys-scientiam`:

- Issue #549 — quota-bound DCP replacement initiative.
- PR #550 — SROF foundation.
- PR #556 — operator kit and read-only gateway expansion.

Those records remain historical evidence.

## New authority

This repository is now the canonical technical source for Remote Operations.

`profesys-scientiam` becomes an integrator/consumer, not the owner.

## Migration rules

- preserve historical references;
- sanitize environment-specific examples;
- do not copy secrets, keys or runtime credentials;
- validate gateway tests after path relocation;
- validate deployment assets before physical rollout;
- do not remove the old copy until the new repository is verified.

## DCP policy

DCP remains available during migration.

Target lifecycle:

`CRITICAL -> PARALLEL -> FALLBACK_NON_CRITICAL -> OPTIONAL_RETIREMENT`

No demotion occurs without evidence from outage drills.
