# SROF through Cloudflare Tunnel + Access

**Status:** PREPARED / ACCOUNT AUTHORIZATION REQUIRED  
**Purpose:** provide a neutral, permanent HTTPS transport for the private SROF MCP gateway without opening inbound ports.

## Target path

```text
MCP client
  → https://<SROF_PUBLIC_HOSTNAME>/mcp
  → Cloudflare Access
  → Cloudflare Tunnel
  → http://127.0.0.1:8765/mcp
  → SROF policy / receipts
  → governed OpenSSH
  → ThinkPad / SERVER
```

## Security invariants

- No public SSH.
- No inbound firewall rule for TCP/8765.
- SROF stays bound to `127.0.0.1:8765`.
- Cloudflare Tunnel is outbound-only from `profesys-scientiam`.
- Access identity/policy is mandatory before operational use.
- DCP is retired.
- GitHub Actions are not a remote transport.
- Secrets and tunnel tokens never enter Git.

## Cloudflare account objects required

1. A Cloudflare zone/domain already managed by the account.
2. A tunnel named, for example, `scientiam-srof`.
3. One published application route:
   - hostname: `<SROF_PUBLIC_HOSTNAME>`
   - service/origin: `http://127.0.0.1:8765`
4. One Cloudflare Access application for that hostname.
5. Identity policy limited to the Founder / explicitly authorized operators.
6. Managed OAuth enabled for MCP-capable non-browser clients, when used.
7. Access logs enabled and retained according to PROFESYS policy.

## Managed OAuth note

Cloudflare Access Managed OAuth is appropriate for non-browser MCP clients. When enabled for an MCP server application, the origin must validate the Access JWT delivered by Cloudflare in the `Cf-Access-Jwt-Assertion` header.

Therefore production activation has two gates:

```text
CLOUDFLARE_TUNNEL = PASS
CLOUDFLARE_ACCESS_JWT_VALIDATION = PASS
```

Do not switch the operational endpoint to LIVE before both pass.

## Dashboard actions the Founder can perform remotely

These do not require physical access to the server:

1. Confirm the target domain is active in Cloudflare.
2. Open **Zero Trust → Networks / Tunnels** and create `scientiam-srof`.
3. Do **not** expose SSH.
4. Reserve the public hostname, for example `srof.<your-domain>`.
5. Create an Access application for that hostname.
6. Create an Allow policy restricted to the Founder identity (and later explicit operators).
7. Enable Managed OAuth on the MCP application when the client path requires OAuth.
8. Record only these non-secret values:
   - public hostname;
   - tunnel UUID;
   - Cloudflare team domain;
   - Access application audience/AUD.
9. Never paste the tunnel token, service-token secret, API token, or private key into chat or Git.

## Server actions for later

When someone has server access:

1. install the current `cloudflared`;
2. install/authenticate the tunnel credentials/token locally;
3. map the tunnel to `http://127.0.0.1:8765`;
4. keep SROF loopback-only;
5. configure Access JWT verification in SROF;
6. run:
   ```bash
   SROF_PUBLIC_HOSTNAME=<hostname> deploy/cloudflare/preflight.sh
   ```
7. verify external OAuth + MCP discovery;
8. verify `hosts_list` and both `host_health`;
9. verify durable SROF receipts.

## Acceptance

```text
SROF_LOCAL_GATEWAY=PASS
CLOUDFLARED_ACTIVE=PASS
PUBLIC_HTTPS_MCP=PASS
ACCESS_POLICY=PASS
MANAGED_OAUTH=PASS
ACCESS_JWT_VALIDATION=PASS
MCP_TOOL_DISCOVERY=PASS
HOST_SERVER=PASS
HOST_THINKPAD=PASS
RECEIPT_READBACK=PASS
DCP_USED=NO
GITHUB_ACTIONS_TRANSPORT=NO
```
