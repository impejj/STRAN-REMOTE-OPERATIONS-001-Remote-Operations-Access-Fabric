# Evidence

This directory defines conventions for non-secret verification evidence.

Do not commit raw receipts, logs or screenshots that contain:
- credentials;
- tokens;
- private keys;
- personal data;
- confidential business data;
- internal secrets.

Preferred committed evidence is metadata-only:
- test/run identifier;
- timestamp;
- tool/capability;
- target class;
- result;
- hash/reference to protected durable evidence.

Protected runtime receipts belong outside Git.
