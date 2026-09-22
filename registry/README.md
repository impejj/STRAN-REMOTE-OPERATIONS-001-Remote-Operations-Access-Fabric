# Governed Host Registry

Committed registry files are schemas and sanitized examples only.

Live host registries must be stored outside Git and may include:
- host identifiers;
- SSH aliases;
- capabilities;
- allowed roots;
- allowed services;
- allowed containers;
- allowed repositories;
- lifecycle state.

Do not store private keys, credentials, tokens or sensitive network details in this repository.

Lifecycle progression:

`REGISTERED -> AUTHORIZED -> HEALTH_OK -> EXECUTION_OK -> EVIDENCE_OK -> PRODUCTION_READY`
