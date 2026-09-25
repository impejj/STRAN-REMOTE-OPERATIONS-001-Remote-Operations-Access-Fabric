#!/usr/bin/env python3
"""Minimal OpenAI Responses API -> SCIENTIAM SROF MCP client.

Secrets are read from environment variables and are never written to evidence.
The MCP surface is intentionally restricted to SROF read-only tools.
"""

from __future__ import annotations

import argparse
import base64
import datetime as dt
import hashlib
from http.server import BaseHTTPRequestHandler, HTTPServer
import json
import os
from pathlib import Path
import secrets
import sys
import urllib.error
import urllib.parse
import urllib.request
import webbrowser
from typing import Any

DEFAULT_OPENAI_URL = "https://api.openai.com/v1/responses"
DEFAULT_SROF_URL = "https://srof.scientiam.com.ar/mcp"
DEFAULT_SROF_OAUTH_ISSUER = "https://auth.scientiam.com.ar/realms/scientiam-srof"
DEFAULT_SROF_OAUTH_CLIENT_ID = "srof-openai-responses-cli"
DEFAULT_SROF_OAUTH_PORT = 8766

READ_ONLY_TOOLS = [
    "hosts_list",
    "host_health",
    "fs_list",
    "fs_read",
    "fs_find",
    "process_list",
    "service_status",
    "docker_ps",
    "docker_logs",
    "git_status",
    "git_diff",
    "journal_tail",
    "network_listeners",
]


class ConfigurationError(RuntimeError):
    pass


def require_env(name: str) -> str:
    value = os.environ.get(name, "").strip()
    if not value:
        raise ConfigurationError(f"missing required environment variable: {name}")
    return value


def normalize_bearer(value: str) -> str:
    value = value.strip()
    return value if value.lower().startswith("bearer ") else f"Bearer {value}"


def _get_json(url: str, timeout: int = 20) -> dict[str, Any]:
    request = urllib.request.Request(url, headers={"Accept": "application/json"})
    with urllib.request.urlopen(request, timeout=timeout) as response:
        return json.load(response)


def _post_form_json(url: str, form: dict[str, str], timeout: int = 20) -> dict[str, Any]:
    request = urllib.request.Request(
        url,
        data=urllib.parse.urlencode(form).encode("utf-8"),
        method="POST",
        headers={
            "Accept": "application/json",
            "Content-Type": "application/x-www-form-urlencoded",
        },
    )
    with urllib.request.urlopen(request, timeout=timeout) as response:
        return json.load(response)


def _pkce_challenge(verifier: str) -> str:
    digest = hashlib.sha256(verifier.encode("ascii")).digest()
    return base64.urlsafe_b64encode(digest).rstrip(b"=").decode("ascii")


def oauth_pkce_login(
    *,
    issuer: str,
    client_id: str,
    port: int,
    open_browser: bool,
    timeout: int = 300,
) -> str:
    issuer = issuer.rstrip("/")
    discovery = _get_json(f"{issuer}/.well-known/openid-configuration")
    if discovery.get("issuer", "").rstrip("/") != issuer:
        raise RuntimeError("OIDC discovery issuer mismatch")
    if "S256" not in (discovery.get("code_challenge_methods_supported") or []):
        raise RuntimeError("OIDC provider does not advertise PKCE S256")

    authorization_endpoint = discovery.get("authorization_endpoint")
    token_endpoint = discovery.get("token_endpoint")
    if not authorization_endpoint or not token_endpoint:
        raise RuntimeError("OIDC discovery missing authorization/token endpoint")

    verifier = secrets.token_urlsafe(64)
    challenge = _pkce_challenge(verifier)
    state = secrets.token_urlsafe(32)
    redirect_uri = f"http://127.0.0.1:{port}/callback"
    result: dict[str, str] = {}

    class CallbackHandler(BaseHTTPRequestHandler):
        def do_GET(self) -> None:  # noqa: N802
            parsed = urllib.parse.urlparse(self.path)
            if parsed.path != "/callback":
                self.send_response(404)
                self.end_headers()
                return

            query = urllib.parse.parse_qs(parsed.query)
            received_state = (query.get("state") or [""])[0]
            if received_state != state:
                result["error"] = "oauth_state_mismatch"
                status = 400
                message = "SROF OAuth failed: state mismatch. You may close this tab."
            elif query.get("error"):
                result["error"] = (query.get("error") or ["oauth_error"])[0]
                result["error_description"] = (query.get("error_description") or [""])[0]
                status = 400
                message = "SROF OAuth was not completed. You may close this tab."
            else:
                result["code"] = (query.get("code") or [""])[0]
                status = 200
                message = "SROF OAuth completed. You may close this tab and return to SCIENTIAM."

            body = (
                "<!doctype html><html><head><meta charset='utf-8'>"
                "<title>SCIENTIAM SROF OAuth</title></head><body>"
                f"<p>{message}</p></body></html>"
            ).encode("utf-8")
            self.send_response(status)
            self.send_header("Content-Type", "text/html; charset=utf-8")
            self.send_header("Content-Length", str(len(body)))
            self.end_headers()
            self.wfile.write(body)

        def log_message(self, format: str, *args: object) -> None:
            return

    server = HTTPServer(("127.0.0.1", port), CallbackHandler)
    server.timeout = timeout

    auth_query = urllib.parse.urlencode(
        {
            "response_type": "code",
            "client_id": client_id,
            "redirect_uri": redirect_uri,
            "scope": "openid srof:read",
            "state": state,
            "code_challenge": challenge,
            "code_challenge_method": "S256",
        }
    )
    authorization_url = f"{authorization_endpoint}?{auth_query}"

    print("SROF OAuth login required.", file=sys.stderr)
    print(f"Open this URL if the browser does not open automatically:\n{authorization_url}", file=sys.stderr)
    if open_browser:
        webbrowser.open(authorization_url, new=1, autoraise=True)

    server.handle_request()
    server.server_close()

    if result.get("error"):
        detail = result.get("error_description", "")
        raise RuntimeError(f"SROF OAuth failed: {result['error']} {detail}".strip())
    code = result.get("code")
    if not code:
        raise RuntimeError("SROF OAuth callback timed out or returned no authorization code")

    token_response = _post_form_json(
        token_endpoint,
        {
            "grant_type": "authorization_code",
            "client_id": client_id,
            "code": code,
            "redirect_uri": redirect_uri,
            "code_verifier": verifier,
        },
    )
    access_token = token_response.get("access_token")
    if not isinstance(access_token, str) or not access_token:
        raise RuntimeError("SROF OAuth token endpoint returned no access_token")
    return access_token


def resolve_srof_access_token(args: argparse.Namespace) -> str:
    existing = os.environ.get("SROF_ACCESS_TOKEN", "").strip()
    if existing:
        return existing
    return oauth_pkce_login(
        issuer=args.oauth_issuer,
        client_id=args.oauth_client_id,
        port=args.oauth_port,
        open_browser=not args.no_browser,
        timeout=args.oauth_timeout,
    )


def build_request(
    *,
    prompt: str,
    model: str,
    srof_url: str,
    srof_access_token: str,
    allowed_tools: list[str] | None = None,
) -> dict[str, Any]:
    tools = allowed_tools or READ_ONLY_TOOLS
    return {
        "model": model,
        "input": prompt,
        "tools": [
            {
                "type": "mcp",
                "server_label": "scientiam_srof",
                "server_description": (
                    "SCIENTIAM governed read-only remote operations over SROF/OpenSSH. "
                    "Use only for authorized PROFESYS/SCIENTIAM host inspection."
                ),
                "server_url": srof_url,
                "authorization": normalize_bearer(srof_access_token),
                "allowed_tools": tools,
                "require_approval": "never",
            }
        ],
    }


def post_json(url: str, *, api_key: str, payload: dict[str, Any], timeout: int) -> dict[str, Any]:
    data = json.dumps(payload).encode("utf-8")
    request = urllib.request.Request(
        url,
        data=data,
        method="POST",
        headers={
            "Authorization": f"Bearer {api_key}",
            "Content-Type": "application/json",
        },
    )
    try:
        with urllib.request.urlopen(request, timeout=timeout) as response:
            return json.load(response)
    except urllib.error.HTTPError as exc:
        body = exc.read().decode("utf-8", errors="replace")
        raise RuntimeError(f"OpenAI API HTTP {exc.code}: {body}") from exc
    except urllib.error.URLError as exc:
        raise RuntimeError(f"OpenAI API transport error: {exc}") from exc


def _extract_output_text(response: dict[str, Any]) -> str | None:
    if response.get("output_text"):
        return str(response["output_text"])

    chunks: list[str] = []
    for item in response.get("output", []) or []:
        if item.get("type") != "message":
            continue
        for content in item.get("content", []) or []:
            if content.get("type") in {"output_text", "text"} and content.get("text"):
                chunks.append(str(content["text"]))
    return "\n".join(chunks) or None


def collect_mcp_events(response: dict[str, Any]) -> dict[str, Any]:
    discovered: list[str] = []
    calls: list[dict[str, Any]] = []
    errors: list[dict[str, Any]] = []

    for item in response.get("output", []):
        item_type = item.get("type")
        if item_type == "mcp_list_tools":
            for tool in item.get("tools", []) or []:
                name = tool.get("name")
                if name:
                    discovered.append(name)
        elif item_type == "mcp_call":
            event = {
                "name": item.get("name"),
                "arguments": item.get("arguments"),
                "output": item.get("output"),
                "error": item.get("error"),
                "server_label": item.get("server_label"),
            }
            calls.append(event)
            if event["error"]:
                errors.append(event)

    return {
        "response_id": response.get("id"),
        "discovered_tools": sorted(set(discovered)),
        "calls": calls,
        "errors": errors,
        "output_text": _extract_output_text(response),
    }


def called_host_health_targets(summary: dict[str, Any]) -> set[str]:
    targets: set[str] = set()
    for call in summary.get("calls", []):
        if call.get("name") != "host_health":
            continue
        raw = call.get("arguments")
        if isinstance(raw, dict):
            args = raw
        elif isinstance(raw, str):
            try:
                args = json.loads(raw)
            except json.JSONDecodeError:
                continue
        else:
            continue
        host_id = args.get("host_id")
        if isinstance(host_id, str) and host_id:
            targets.add(host_id)
    return targets


def probe_prompt(hosts: list[str]) -> str:
    host_text = ", ".join(hosts)
    return (
        "This is the SROF read-only acceptance probe. "
        "First call hosts_list. Then call host_health for each of these hosts: "
        f"{host_text}. Do not use any non-SROF tool and do not mutate anything. "
        "Return a concise health summary after the tool calls."
    )


def write_evidence(directory: str, summary: dict[str, Any]) -> Path:
    target = Path(directory).expanduser().resolve()
    target.mkdir(parents=True, exist_ok=True)
    stamp = dt.datetime.now(dt.timezone.utc).strftime("%Y%m%dT%H%M%SZ")
    path = target / f"srof-openai-probe-{stamp}.json"
    payload = {
        "schema": "SROF_OPENAI_CLIENT_RECEIPT_V1",
        "created_at": dt.datetime.now(dt.timezone.utc).isoformat(),
        **summary,
    }
    path.write_text(json.dumps(payload, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")
    return path


def parse_args(argv: list[str]) -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="OpenAI Responses -> SCIENTIAM SROF MCP client")
    mode = parser.add_mutually_exclusive_group(required=True)
    mode.add_argument("--probe", action="store_true", help="run hosts_list + host_health acceptance probe")
    mode.add_argument("--prompt", help="send a custom read-only prompt")
    parser.add_argument("--host", action="append", default=[], help="probe host; repeat for multiple hosts")
    parser.add_argument("--model", default=os.environ.get("OPENAI_MODEL"), help="OpenAI model; or OPENAI_MODEL")
    parser.add_argument("--openai-url", default=os.environ.get("OPENAI_RESPONSES_URL", DEFAULT_OPENAI_URL))
    parser.add_argument("--srof-url", default=os.environ.get("SROF_MCP_URL", DEFAULT_SROF_URL))
    parser.add_argument("--timeout", type=int, default=int(os.environ.get("SROF_OPENAI_TIMEOUT", "120")))
    parser.add_argument("--evidence-dir", default=os.environ.get("SROF_OPENAI_EVIDENCE_DIR"))
    parser.add_argument(
        "--oauth-issuer",
        default=os.environ.get("SROF_OAUTH_ISSUER", DEFAULT_SROF_OAUTH_ISSUER),
    )
    parser.add_argument(
        "--oauth-client-id",
        default=os.environ.get("SROF_OAUTH_CLIENT_ID", DEFAULT_SROF_OAUTH_CLIENT_ID),
    )
    parser.add_argument(
        "--oauth-port",
        type=int,
        default=int(os.environ.get("SROF_OAUTH_PORT", str(DEFAULT_SROF_OAUTH_PORT))),
    )
    parser.add_argument(
        "--oauth-timeout",
        type=int,
        default=int(os.environ.get("SROF_OAUTH_TIMEOUT", "300")),
    )
    parser.add_argument(
        "--no-browser",
        action="store_true",
        help="print OAuth URL instead of opening the default browser",
    )
    parser.add_argument("--json", action="store_true", help="print structured MCP summary")
    return parser.parse_args(argv)


def main(argv: list[str] | None = None) -> int:
    args = parse_args(argv or sys.argv[1:])

    try:
        openai_key = require_env("OPENAI_API_KEY")
        model = args.model or require_env("OPENAI_MODEL")
        srof_token = resolve_srof_access_token(args)
    except (ConfigurationError, RuntimeError, urllib.error.URLError, urllib.error.HTTPError) as exc:
        print(f"CONFIGURATION_ERROR: {exc}", file=sys.stderr)
        return 2

    hosts = args.host or ["PROFESYS-SCIENTIAM", "THINKPAD-E470"]
    prompt = probe_prompt(hosts) if args.probe else args.prompt

    payload = build_request(
        prompt=prompt,
        model=model,
        srof_url=args.srof_url,
        srof_access_token=srof_token,
    )

    try:
        response = post_json(
            args.openai_url,
            api_key=openai_key,
            payload=payload,
            timeout=args.timeout,
        )
    except RuntimeError as exc:
        print(f"REQUEST_FAILED: {exc}", file=sys.stderr)
        return 3

    summary = collect_mcp_events(response)

    if args.evidence_dir:
        evidence_path = write_evidence(args.evidence_dir, summary)
        summary["client_evidence_path"] = str(evidence_path)

    if args.json:
        print(json.dumps(summary, indent=2, ensure_ascii=False))
    else:
        if summary.get("output_text"):
            print(summary["output_text"])
        else:
            print(json.dumps(summary, indent=2, ensure_ascii=False))

    if summary["errors"]:
        return 4

    if args.probe:
        called = [call.get("name") for call in summary["calls"]]
        health_targets = called_host_health_targets(summary)
        missing_hosts = sorted(set(hosts) - health_targets)
        if "hosts_list" not in called or missing_hosts:
            print(
                "ACCEPTANCE_FAILED: expected hosts_list and host_health for every requested host; "
                f"missing_hosts={missing_hosts}",
                file=sys.stderr,
            )
            return 5

    return 0


if __name__ == "__main__":
    raise SystemExit(main())
