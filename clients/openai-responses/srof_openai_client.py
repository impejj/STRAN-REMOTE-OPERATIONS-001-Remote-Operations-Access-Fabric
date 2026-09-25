#!/usr/bin/env python3
"""Minimal OpenAI Responses API -> SCIENTIAM SROF MCP client.

Secrets are read from environment variables and are never written to evidence.
The MCP surface is intentionally restricted to SROF read-only tools.
"""

from __future__ import annotations

import argparse
import datetime as dt
import json
import os
from pathlib import Path
import sys
import urllib.error
import urllib.request
from typing import Any

DEFAULT_OPENAI_URL = "https://api.openai.com/v1/responses"
DEFAULT_SROF_URL = "https://srof.scientiam.com.ar/mcp"

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
        "output_text": response.get("output_text"),
    }


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
    parser.add_argument("--json", action="store_true", help="print structured MCP summary")
    return parser.parse_args(argv)


def main(argv: list[str] | None = None) -> int:
    args = parse_args(argv or sys.argv[1:])

    try:
        openai_key = require_env("OPENAI_API_KEY")
        srof_token = require_env("SROF_ACCESS_TOKEN")
        model = args.model or require_env("OPENAI_MODEL")
    except ConfigurationError as exc:
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
        if "hosts_list" not in called or "host_health" not in called:
            print(
                "ACCEPTANCE_FAILED: expected hosts_list and host_health MCP calls were not both observed",
                file=sys.stderr,
            )
            return 5

    return 0


if __name__ == "__main__":
    raise SystemExit(main())
