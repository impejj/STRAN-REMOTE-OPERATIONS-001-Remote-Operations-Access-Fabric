# OpenAI Responses → SROF client (P0)

This client closes the provider-side binding gap without changing SROF.

```text
SCIENTIAM client
  -> OpenAI Responses API
  -> remote MCP tool (allowed_tools = SROF read-only surface)
  -> https://srof.scientiam.com.ar/mcp
  -> SROF OAuth Resource Server
  -> governed OpenSSH
  -> PROFESYS-SCIENTIAM / THINKPAD-E470
```

## Security

- GitHub remains SCM only.
- DCP is not used.
- No arbitrary shell is exposed.
- `OPENAI_API_KEY` and `SROF_ACCESS_TOKEN` are environment-only secrets.
- The client never writes either secret to evidence.
- `allowed_tools` is hard-bounded to the current SROF read-only surface.
- `require_approval=never` applies only because this client exposes read-only tools. Any future mutation client must use an explicit approval policy and a separate acceptance gate.

## Prerequisites

1. Python 3.11+.
2. An OpenAI API key.
3. The Keycloak native client `srof-openai-responses-cli` configured by
   `deploy/native-auth/configure-openai-responses-client.sh`.
4. An explicit `OPENAI_MODEL` value compatible with remote MCP in the Responses API.

By default the client performs Authorization Code + PKCE against the SROF Keycloak realm.
The Founder completes password + TOTP in the browser; the callback is loopback-only and
the access token remains in process memory. `SROF_ACCESS_TOKEN` is still accepted for
controlled testing, but is not the normal P0 path.

## Acceptance probe

```bash
export OPENAI_API_KEY='...'
export OPENAI_MODEL='...'

python srof_openai_client.py --probe --json
```

The default browser opens the SROF Keycloak login. Complete password + TOTP; the client
then exchanges the authorization code using PKCE and immediately runs the read-only probe.

Expected observed calls:

```text
hosts_list
host_health(PROFESYS-SCIENTIAM)
host_health(THINKPAD-E470)
```

Optionally persist a sanitized client-side receipt:

```bash
export SROF_OPENAI_EVIDENCE_DIR=/var/lib/scientiam/remote-ops/client-receipts
python srof_openai_client.py --probe --json
```

SROF remains authoritative for remote-operation receipts.

## Unit tests

```bash
python -m unittest discover -s tests -v
```

## Definition of LIVE

Do not declare this adapter LIVE until the probe observes the expected MCP calls and the corresponding SROF server-side receipts show the expected actor/client/scope binding.
