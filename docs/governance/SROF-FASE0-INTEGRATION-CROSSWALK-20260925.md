# SROF Fase 0 — Integration Crosswalk — 2026-09-25

**Status:** CURRENT CANDIDATE / EVIDENCE-BASED
**Managed object:** STRAN-REMOTE-OPERATIONS-001
**Purpose:** identify what SROF must reuse from SCIENTIAM before adding new orchestration components.

## Executive result

SROF should NOT create a new scheduler/resource-admission engine.

The current SCIENTIAM repository already contains a substantial execution stack:

- WGE admission contracts and deterministic engine;
- PENTA slot/runtime-resource model;
- worker isolation plans;
- SoftwareExecutionPack and execution receipts;
- worker certification canon;
- technical standards resolver;
- AI provider execution adapter;
- a Prefect development stack.

The minimum delta for SROF is therefore:

```text
ChatGPT / adapter
  -> SROF Relay
  -> translate SROF request into existing SCIENTIAM execution/resource contracts
  -> WGE / existing execution plane
  -> certified worker / runtime resource
  -> receipt / evidence
```

SROF differentiates itself through remote-resource execution, typed machine operations, identity/policy/evidence integration and provider-independent adapters.

## 1. WGE / runtime-resource reuse — CONFIRMED

Source:
`services/agent-control-plane/app/work_generation/contracts.py`
`services/agent-control-plane/app/work_generation/engine.py`

Existing capabilities already model:

- `MachineRequirement.requires_machine`;
- `required_capabilities`;
- `permitted_resources`;
- `preferred_resource`;
- runtime resource health;
- runtime availability window;
- lease availability;
- resource capabilities;
- evidence reference;
- direct vs runtime-resource execution;
- `WAITING_RUNTIME_RESOURCE`;
- `RESOURCE_BUSY` semantics;
- priority queue ordering.

Conclusion:

> SROF must register/provide runtime-resource evidence and execution, not replace WGE admission.

## 2. Worker model — REUSE REQUIRED

Source:
`docs/20_standards/worker-certification/STD-SC-WORKER-CERTIFICATION-001.md`

Worker certification is already CANON / FOUNDER_APPROVED and capability-scoped.

SROF workers must use this certification lifecycle and must NOT invent a parallel worker-readiness authority.

Related scorecard:
`SPEC-SC-WORKER-CAPABILITY-SCORECARD-001.schema.json`

Conclusion:

> READ/DEV/OPS SROF workers are worker profiles/capabilities under the existing certification standard.

## 3. Software Factory execution contracts — REUSE / COMPOSE

Source:
`services/agent-control-plane/app/software_factory/contracts.py`

Existing `SoftwareExecutionPack` already includes:

- work lineage;
- objective/non-goals;
- repository;
- data class;
- risk class;
- workload class;
- required capabilities;
- standards;
- context pack;
- acceptance criteria;
- required gates;
- budget;
- allowed providers;
- prohibited actions;
- retry maximum;
- human gate.

Existing `ExecutionReceipt` already validates UUIDv7 execution/correlation identifiers and records policy/provider/time/cost/evidence.

Conclusion:

> srof.request.v2 should be a remote-operation/resource envelope that composes with existing execution packs instead of replacing them.

## 4. Worker isolation — REUSE

Source:
`services/agent-control-plane/app/software_factory/worker.py`

Existing worker isolation already defines:

- base ref;
- candidate branch;
- ephemeral worktree;
- allowed write paths;
- required gate commands;
- no push;
- no merge;
- no deploy;
- fail-closed authorization.

Conclusion:

> DEV worker mutation should integrate with this isolation plan.

## 5. Technical standards resolver — REUSE

Source:
`tools/agent_governance/agent_governance/technical_resolver.py`

The resolver:

- consumes CURRENT technical profiles;
- requires reproducible repository evidence;
- returns UNKNOWN on missing/conflicting evidence;
- emits context digest;
- fails closed for missing standards.

Conclusion:

> SROF does not create a parallel technical-policy resolver.

## 6. WGE explicitly is not a scheduler

Source:
`docs/40_product/capability-fabric/WGE-MVP-SLOT-WORKER-001.md`

Existing declaration:

> WGE = Work Generation/Admission Engine. It is not the worker and it is not a new scheduler.

The PENTA slot remains the autonomous worker. Physical machines are runtime resources.

Conclusion:

> SROF maps naturally to the runtime-resource/execution side of this model.

## 7. Prefect — PRESENT BUT AUTHORITY NOT YET PROVEN

Source:
`platform/infrastructure/docker/stacks/scientiam-prefect-dev/docker-compose.yml`

Verified in repository:

- Prefect 3.8.0 development server;
- PostgreSQL;
- Redis;
- Prefect services;
- loopback-only API.

The compose file does not itself prove that Prefect is the authoritative production execution runtime for WGE/SROF, nor does it define the SROF worker model.

Decision:

> Do not rebuild a scheduler, but also do not make Prefect a hard SROF dependency until runtime/authority readback proves its actual role.

## 8. PENTA federated execution network — STRONG ALIGNMENT

Source:
`docs/40_product/capability-fabric/PENTA-FEDERATED-EXECUTION-NETWORK-001.md`

Existing model already distinguishes:

- slot != engine != network;
- machine = execution resource, not worker;
- health/readiness preflight;
- resource windows;
- leases;
- data/authority boundaries;
- durable evidence/readback;
- requeue on unavailable machine.

Conclusion:

> SROF should become the governed runtime-resource fabric used by PENTA/WGE rather than a competing execution network.

## 9. AI execution routing — REUSE WHERE APPLICABLE

Source:
`services/ai-platform-api/app/execution_adapter.py`

Existing adapter already provides:

- provider-neutral routing;
- data-class gates;
- workload policy;
- capacity/provider restrictions;
- audit decision object;
- no automatic external execution for non-public/synthetic data.

Conclusion:

> local SROF AI workers should integrate as an eligible governed execution provider/capability instead of defining a second model-router.

## 10. Minimum SROF delta

Build now:

1. `SROF Relay` adapter normalization.
2. SROF -> `RuntimeResourceSnapshot` projection.
3. Runtime-resource health/lease evidence provider.
4. Typed remote operations executor.
5. SROF receipt -> existing evidence/receipt crosswalk.
6. Certified worker profiles for READ/DEV/OPS.
7. Local Console / break-glass adapter.

Do NOT build now:

- another WGE;
- another scheduler;
- another worker certification system;
- another technical standards resolver;
- another vector store;
- another provider router.

## 11. Immediate implementation slice

The next code slice should be:

```text
SROF relay health
 -> RuntimeResourceSnapshot(
      resource_id="THINKPAD-E470",
      health="HEALTHY",
      window_open=true,
      lease_available=true,
      capabilities=[...],
      evidence_ref=<SROF receipt>
    )
 -> WGE admission
 -> existing slot/resource decision
```

Acceptance:

- existing WGE tests remain green;
- new SROF projection tests pass;
- unavailable SROF resource maps to WAITING_RUNTIME_RESOURCE, not FAILED;
- evidence_ref points to durable SROF receipt;
- no new scheduling authority is introduced.

## 12. Worker-assisted verification

The persistent SROF Relay POC has a bounded `fase0_probe` operation that:

- verifies required source files exist on THINKPAD;
- runs selected WGE, worker-isolation, worker-certification and technical-resolver tests;
- emits a SROF receipt;
- executes through the owned Relay rather than GitHub machine commands.

This is the first explicit use of our own worker runtime to validate the architecture it will later execute.

## Final decision

`REUSE_BEFORE_BUILD = REQUIRED`

SROF is not a new execution operating system.

SROF is the sovereign remote-runtime, machine-operation and adapter layer that plugs into the existing SCIENTIAM execution/governance fabric.
