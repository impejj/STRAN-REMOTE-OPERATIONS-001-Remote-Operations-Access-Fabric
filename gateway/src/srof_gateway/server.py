from __future__ import annotations

import json
import os
from pathlib import Path

from mcp.server.fastmcp import FastMCP

from .policy import (
    HostPolicy,
    require_capability,
    require_container,
    require_path,
    require_repository,
    require_service,
)
from .ssh_runner import SshRunner


mcp = FastMCP("SCIENTIAM Remote Operations Fabric")
HOSTS_FILE = Path(os.environ.get("SROF_HOSTS_FILE", "/etc/scientiam/remote-ops/hosts.json"))
RECEIPTS = Path(os.environ.get("SROF_RECEIPT_DIR", "/var/lib/scientiam/remote-ops/receipts"))
runner = SshRunner(RECEIPTS)

_REMOTE_FS = r"""
import fnmatch,json,os,sys
op,path,roots_json=sys.argv[1],sys.argv[2],sys.argv[3]
roots=[os.path.realpath(x) for x in json.loads(roots_json)]
real=os.path.realpath(path)
if not any(real==root or real.startswith(root.rstrip('/')+'/') for root in roots):
    print(json.dumps({'error':'PATH_OUTSIDE_ALLOWED_ROOTS','path':path}))
    raise SystemExit(77)
if op=='list':
    limit=int(sys.argv[4])
    rows=[]
    with os.scandir(real) as it:
        for entry in it:
            rows.append({'name':entry.name,'path':entry.path,'is_dir':entry.is_dir(follow_symlinks=False),'is_file':entry.is_file(follow_symlinks=False),'is_symlink':entry.is_symlink()})
            if len(rows)>=limit: break
    print(json.dumps({'path':real,'entries':rows}))
elif op=='read':
    limit=int(sys.argv[4])
    if not os.path.isfile(real):
        print(json.dumps({'error':'NOT_REGULAR_FILE','path':real}))
        raise SystemExit(78)
    with open(real,'rb') as fh: data=fh.read(limit+1)
    truncated=len(data)>limit
    data=data[:limit]
    print(json.dumps({'path':real,'text':data.decode('utf-8','replace'),'bytes':len(data),'truncated':truncated}))
elif op=='find':
    pattern=sys.argv[4]; limit=int(sys.argv[5]); rows=[]
    for base,dirs,files in os.walk(real,followlinks=False):
        dirs[:]=[d for d in dirs if not os.path.islink(os.path.join(base,d))]
        for name in dirs+files:
            if fnmatch.fnmatch(name,pattern):
                rows.append(os.path.join(base,name))
                if len(rows)>=limit: break
        if len(rows)>=limit: break
    print(json.dumps({'root':real,'pattern':pattern,'matches':rows,'truncated':len(rows)>=limit}))
else:
    print(json.dumps({'error':'UNKNOWN_OPERATION'})); raise SystemExit(79)
"""


def _hosts() -> dict[str, HostPolicy]:
    raw = json.loads(HOSTS_FILE.read_text(encoding="utf-8"))
    result: dict[str, HostPolicy] = {}
    for item in raw.get("hosts", []):
        result[item["host_id"]] = HostPolicy(
            host_id=item["host_id"],
            ssh_alias=item["ssh_alias"],
            capabilities=frozenset(item.get("capabilities", [])),
            allowed_roots=tuple(item.get("allowed_roots", [])),
            allowed_services=frozenset(item.get("allowed_services", [])),
            allowed_containers=frozenset(item.get("allowed_containers", [])),
            allowed_repositories=frozenset(item.get("allowed_repositories", [])),
            lifecycle_state=item["lifecycle_state"],
        )
    return result


def _host(host_id: str) -> HostPolicy:
    host = _hosts().get(host_id)
    if host is None:
        raise KeyError(f"unknown host {host_id}")
    return host


def _json_receipt(receipt) -> dict[str, object]:
    payload: dict[str, object] = {"receipt": receipt.__dict__, "ok": receipt.exit_code == 0}
    if receipt.stdout.strip():
        try:
            payload["data"] = json.loads(receipt.stdout)
        except json.JSONDecodeError:
            payload["data"] = receipt.stdout
    return payload


@mcp.tool()
def hosts_list() -> list[dict[str, object]]:
    return [
        {"host_id": h.host_id, "capabilities": sorted(h.capabilities), "lifecycle_state": h.lifecycle_state}
        for h in _hosts().values()
    ]


@mcp.tool()
def host_health(host_id: str) -> dict[str, object]:
    h = _host(host_id)
    require_capability(h, "PROCESS")
    r = runner.run_argv(h.host_id, h.ssh_alias, "host_health", ["sh", "-lc", "hostname; uptime; df -P / | tail -1"])
    return {"receipt": r.__dict__, "ok": r.exit_code == 0}


@mcp.tool()
def fs_list(host_id: str, path: str, limit: int = 200) -> dict[str, object]:
    h = _host(host_id)
    require_path(h, path)
    limit = max(1, min(int(limit), 500))
    r = runner.run_argv(h.host_id, h.ssh_alias, "fs_list", ["python3", "-c", _REMOTE_FS, "list", path, json.dumps(h.allowed_roots), str(limit)])
    return _json_receipt(r)


@mcp.tool()
def fs_read(host_id: str, path: str, max_bytes: int = 65536) -> dict[str, object]:
    h = _host(host_id)
    require_path(h, path)
    max_bytes = max(1, min(int(max_bytes), 262144))
    r = runner.run_argv(h.host_id, h.ssh_alias, "fs_read", ["python3", "-c", _REMOTE_FS, "read", path, json.dumps(h.allowed_roots), str(max_bytes)])
    return _json_receipt(r)


@mcp.tool()
def fs_find(host_id: str, root: str, pattern: str, max_results: int = 100) -> dict[str, object]:
    h = _host(host_id)
    require_path(h, root)
    max_results = max(1, min(int(max_results), 500))
    r = runner.run_argv(h.host_id, h.ssh_alias, "fs_find", ["python3", "-c", _REMOTE_FS, "find", root, json.dumps(h.allowed_roots), pattern, str(max_results)])
    return _json_receipt(r)


@mcp.tool()
def process_list(host_id: str, limit: int = 100) -> dict[str, object]:
    h = _host(host_id)
    require_capability(h, "PROCESS")
    limit = max(1, min(int(limit), 300))
    cmd = f"ps -eo pid,ppid,etimes,user,comm,args --sort=-etimes | head -n {limit + 1}"
    r = runner.run_argv(h.host_id, h.ssh_alias, "process_list", ["sh", "-lc", cmd])
    return {"receipt": r.__dict__, "ok": r.exit_code == 0, "text": r.stdout}


@mcp.tool()
def service_status(host_id: str, service: str) -> dict[str, object]:
    h = _host(host_id)
    require_service(h, service)
    r = runner.run_argv(h.host_id, h.ssh_alias, "service_status", ["systemctl", "is-active", "--", service])
    return {"receipt": r.__dict__, "active": r.stdout.strip() == "active"}


@mcp.tool()
def docker_ps(host_id: str) -> dict[str, object]:
    h = _host(host_id)
    require_capability(h, "DOCKER")
    r = runner.run_argv(h.host_id, h.ssh_alias, "docker_ps", ["docker", "ps", "--format", "{{.Names}}\t{{.Status}}"])
    return {"receipt": r.__dict__, "ok": r.exit_code == 0}


@mcp.tool()
def docker_logs(host_id: str, container: str, tail: int = 100) -> dict[str, object]:
    h = _host(host_id)
    require_container(h, container)
    tail = max(1, min(int(tail), 500))
    r = runner.run_argv(h.host_id, h.ssh_alias, "docker_logs", ["docker", "logs", "--tail", str(tail), container])
    return {"receipt": r.__dict__, "ok": r.exit_code == 0}


@mcp.tool()
def git_status(host_id: str, repository: str) -> dict[str, object]:
    h = _host(host_id)
    require_repository(h, repository)
    r = runner.run_argv(h.host_id, h.ssh_alias, "git_status", ["git", "-C", repository, "status", "--short", "--branch"])
    return {"receipt": r.__dict__, "ok": r.exit_code == 0, "text": r.stdout}


@mcp.tool()
def git_diff(host_id: str, repository: str, max_lines: int = 400) -> dict[str, object]:
    h = _host(host_id)
    require_repository(h, repository)
    max_lines = max(1, min(int(max_lines), 1200))
    r = runner.run_argv(h.host_id, h.ssh_alias, "git_diff", ["git", "-C", repository, "diff", "--no-ext-diff", "--"])
    lines = r.stdout.splitlines()
    return {"receipt": r.__dict__, "ok": r.exit_code == 0, "text": "\n".join(lines[:max_lines]), "truncated": len(lines) > max_lines}


@mcp.tool()
def journal_tail(host_id: str, service: str, lines: int = 100) -> dict[str, object]:
    h = _host(host_id)
    require_service(h, service)
    lines = max(1, min(int(lines), 500))
    r = runner.run_argv(h.host_id, h.ssh_alias, "journal_tail", ["journalctl", "--no-pager", "-n", str(lines), "-u", service])
    return {"receipt": r.__dict__, "ok": r.exit_code == 0, "text": r.stdout}


@mcp.tool()
def network_listeners(host_id: str) -> dict[str, object]:
    h = _host(host_id)
    require_capability(h, "NETWORK")
    r = runner.run_argv(h.host_id, h.ssh_alias, "network_listeners", ["ss", "-ltnp"])
    return {"receipt": r.__dict__, "ok": r.exit_code == 0, "text": r.stdout}


def run_gateway() -> None:
    transport = os.environ.get("SROF_MCP_TRANSPORT", "streamable-http")
    if transport == "stdio":
        mcp.run()
        return
    if transport != "streamable-http":
        raise ValueError(f"unsupported SROF_MCP_TRANSPORT={transport!r}")

    host = os.environ.get("SROF_MCP_HOST", "127.0.0.1")
    port = int(os.environ.get("SROF_MCP_PORT", "8765"))
    path = os.environ.get("SROF_MCP_PATH", "/mcp")
    mcp.run(
        transport="streamable-http",
        host=host,
        port=port,
        streamable_http_path=path,
    )


if __name__ == "__main__":
    run_gateway()
