# Authority Boundaries

Remote access is not equivalent to unrestricted authority.

## Default posture

- deny by default;
- least privilege;
- explicit host/capability/path/service/container/repository allowlists;
- no direct AI root;
- no secrets in source control;
- no arbitrary command text sourced from databases or queues;
- mutation requires verification and receipt.

## Human plane

Human interactive access may expose broader operating-system capabilities than the AI plane, but remains subject to identity, MFA, logging and operational policy.

## AI plane

The AI plane exposes named tools, not a general-purpose root shell.

Every operation must resolve:
1. actor;
2. host;
3. requested capability;
4. authority decision;
5. execution;
6. readback/post-condition;
7. durable receipt.

## External exposure

LAN-first is the P0 posture. WAN exposure is a separate security gate and requires authenticated tunneling/reverse proxy, MFA and CISO review.

## Publication

Remote operations does not grant authority to publish externally, deploy to production, rotate credentials or modify business data unless a separate authority explicitly permits it.
