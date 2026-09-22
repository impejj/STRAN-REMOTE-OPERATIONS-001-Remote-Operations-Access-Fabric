# DCP Exit Plan

## Problem
Desktop Commander Remote has been operationally useful but a provider-side monthly quota can interrupt remote administration.

## Policy
DCP may remain available, but it must not be:
- the only server shell path;
- the only ThinkPad shell path;
- the only file-management path;
- the only way AI workers reach infrastructure.

## Transition

### Stage 0 — current
DCP critical.

### Stage 1 — parallel
MeshCentral + SSH + SROF are deployed while DCP remains unchanged.

### Stage 2 — evidence
Run five consecutive remote-operation sessions without DCP:
- health;
- files;
- logs;
- service control;
- transfer.

### Stage 3 — fallback
DCP becomes `FALLBACK_NON_CRITICAL`.

### Stage 4 — optional retirement
Retire only after 30 days of reliable self-hosted operation and successful recovery drill.

## Metrics
- remote operations success rate;
- p95 command latency;
- failed authentication count;
- receipt coverage;
- recovery time after host restart;
- number of tasks blocked by external quota (target 0).
