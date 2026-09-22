# Security Policy

This repository contains remote-operations software and deployment examples.

## Never commit

- private SSH keys;
- API tokens;
- passwords;
- MeshCentral credentials;
- production host-registry secrets;
- private certificates;
- VPN/tunnel credentials;
- unredacted evidence containing secrets.

## Reporting

Treat suspected credential exposure, unauthorized access, privilege escalation, command injection or unsafe remote-execution behavior as P0.

## Design requirements

- least privilege;
- deny by default;
- explicit allowlists;
- no direct AI root;
- key-based remote identities;
- post-condition verification for mutations;
- durable execution receipts;
- LAN-first deployment before any WAN exposure.

Runtime configuration belongs outside Git and should be injected through protected host configuration or a secrets mechanism.
