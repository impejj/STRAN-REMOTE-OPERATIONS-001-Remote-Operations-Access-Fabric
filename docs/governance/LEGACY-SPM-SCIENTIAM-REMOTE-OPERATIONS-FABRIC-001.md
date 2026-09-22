# SPM-SCIENTIAM-REMOTE-OPERATIONS-FABRIC-001

## Mission

Provide a vendor-independent remote operations fabric for PROFESYS/SCIENTIAM that supports human administration and AI-assisted operations without depending on a third-party monthly quota.

## Scope

### Human
- browser-based terminal;
- file management;
- device inventory;
- remote desktop where supported;
- emergency access independent from AI clients.

### AI / automation
- host health;
- filesystem read/list/search under allowed roots;
- process inspection;
- systemd status/restart for allowlisted units;
- Docker status/logs for allowlisted containers;
- Git status/diff and bounded repository actions;
- SCP/rsync transfers;
- structured receipts.

### Federated capacity
Every host or account is a physical execution channel with:
- owner;
- host identity;
- capabilities;
- availability;
- allowed process types;
- allowed data classes;
- quota/cost policy;
- validity window;
- pause/drain/revoke controls.

## Authority model

```
REQUEST
  -> CLASSIFY
  -> AUTHORIZE
  -> ALLOCATE
  -> EXECUTE
  -> VERIFY
  -> RECEIPT
  -> [PUBLICATION GATE if external]
```

## Execution classes

- `READ_ONLY`
- `DETERMINISTIC_WRITE`
- `PRIVILEGED_WRITE`
- `GUI_INTERACTIVE`
- `PUBLICATION`

## Initial hosts

- `THINKPAD-E470` — development/operator workstation.
- `PROFESYS-SCIENTIAM` — production server.
- future contributed workers are registered explicitly; never inferred.

## Status model

`DISCOVERED -> REGISTERED -> AUTHORIZED -> HEALTH_OK -> EXECUTION_OK -> EVIDENCE_OK -> PRODUCTION_READY`

## P0 acceptance

- human can reach server and ThinkPad without DCP;
- AI gateway can execute at least health/list/read/status operations on both hosts;
- one controlled systemd restart passes readback;
- one bounded file transfer passes checksum readback;
- every execution produces a receipt;
- revocation of a host/channel blocks future allocations;
- DCP outage does not block normal remote operations.
