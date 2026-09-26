from __future__ import annotations

import base64
import json
from dataclasses import dataclass
from typing import Any


READ_WORKER_ID = "SROF-WORKER-READ-001"
DEV_WORKER_ID = "SROF-WORKER-DEV-001"


@dataclass(frozen=True)
class WorkerSpec:
    worker_id: str
    role: str
    port: int
    token_file: str
    operations: tuple[str, ...] = ()


WORKERS: dict[str, WorkerSpec] = {
    READ_WORKER_ID: WorkerSpec(
        worker_id=READ_WORKER_ID,
        role="READ",
        port=8781,
        token_file="/etc/scientiam/srof-workers/read.token",
        operations=("fs_list", "fs_read", "fs_find", "git_status", "git_diff"),
    ),
    DEV_WORKER_ID: WorkerSpec(
        worker_id=DEV_WORKER_ID,
        role="DEV",
        port=8782,
        token_file="/etc/scientiam/srof-workers/dev.token",
        operations=(),
    ),
}


_REMOTE_WORKER_HTTP = r"""
import base64,json,sys,urllib.error,urllib.request
method,url,token_file,payload_b64=sys.argv[1],sys.argv[2],sys.argv[3],sys.argv[4]
headers={"Accept":"application/json"}
data=None
if method=="POST":
    try:
        token=open(token_file,encoding="utf-8").read().strip()
    except OSError as exc:
        print(json.dumps({"error":"WORKER_TOKEN_FILE_UNAVAILABLE","detail":type(exc).__name__}))
        raise SystemExit(70)
    if not token:
        print(json.dumps({"error":"WORKER_TOKEN_EMPTY"}))
        raise SystemExit(71)
    headers["Authorization"]="Bearer "+token
    headers["Content-Type"]="application/json"
    data=base64.b64decode(payload_b64.encode("ascii"))
req=urllib.request.Request(url,data=data,headers=headers,method=method)
try:
    with urllib.request.urlopen(req,timeout=15) as response:
        body=response.read(262144)
        print(body.decode("utf-8","replace"))
except urllib.error.HTTPError as exc:
    body=exc.read(262144)
    print(body.decode("utf-8","replace"))
    raise SystemExit(72)
except Exception as exc:
    print(json.dumps({"error":"WORKER_HTTP_FAILED","detail":type(exc).__name__}))
    raise SystemExit(73)
""".strip()


def worker_spec(worker_id: str) -> WorkerSpec:
    try:
        return WORKERS[worker_id]
    except KeyError as exc:
        raise PermissionError(f"worker {worker_id!r} is not allowlisted") from exc


def worker_inventory() -> list[dict[str, Any]]:
    return [
        {
            "worker_id": spec.worker_id,
            "role": spec.role,
            "port": spec.port,
            "operations": list(spec.operations),
        }
        for spec in WORKERS.values()
    ]


def _http_argv(spec: WorkerSpec, method: str, endpoint: str, payload: dict[str, Any] | None = None) -> list[str]:
    if method not in {"GET", "POST"}:
        raise ValueError("unsupported worker HTTP method")
    if endpoint not in {"/health", "/capabilities", "/jobs"}:
        raise ValueError("unsupported worker endpoint")
    if method == "POST" and endpoint != "/jobs":
        raise ValueError("POST is only allowed for /jobs")
    if method == "GET" and endpoint == "/jobs":
        raise ValueError("GET /jobs is not supported")

    encoded = ""
    if payload is not None:
        encoded = base64.b64encode(
            json.dumps(payload, sort_keys=True, separators=(",", ":")).encode("utf-8")
        ).decode("ascii")

    return [
        "python3",
        "-c",
        _REMOTE_WORKER_HTTP,
        method,
        f"http://127.0.0.1:{spec.port}{endpoint}",
        spec.token_file,
        encoded,
    ]


def worker_health_argv(worker_id: str) -> list[str]:
    return _http_argv(worker_spec(worker_id), "GET", "/health")


def worker_capabilities_argv(worker_id: str) -> list[str]:
    return _http_argv(worker_spec(worker_id), "GET", "/capabilities")


def worker_read_job_argv(
    worker_id: str,
    request_id: str,
    operation: str,
    args: dict[str, Any] | None = None,
) -> list[str]:
    spec = worker_spec(worker_id)
    if spec.role != "READ":
        raise PermissionError(f"worker {worker_id!r} is not a READ worker")
    if operation not in spec.operations:
        raise PermissionError(f"READ operation {operation!r} is not allowlisted")
    payload = {
        "schema": "srof.worker.job.v1",
        "request_id": request_id,
        "operation": operation,
        "args": dict(args or {}),
    }
    return _http_argv(spec, "POST", "/jobs", payload)
