#!/usr/bin/env python3
from __future__ import annotations

import hashlib
import json
import os
import re
import shlex
import sqlite3
import subprocess
import threading
import time
import uuid
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import PurePosixPath
from urllib.error import HTTPError
from urllib.parse import urlparse
from urllib.request import Request, urlopen

DATA_DIR = os.environ.get("SROF_RELAY_DATA", "/data")
DB_PATH = os.path.join(DATA_DIR, "relay.sqlite3")
RECEIPTS_DIR = os.path.join(DATA_DIR, "receipts")
LISTEN_HOST = os.environ.get("SROF_RELAY_HOST", "0.0.0.0")
LISTEN_PORT = int(os.environ.get("SROF_RELAY_PORT", "8790"))

THINKPAD_HOST = os.environ.get("SROF_THINKPAD_HOST", "192.168.1.6")
THINKPAD_USER = os.environ.get("SROF_THINKPAD_USER", "scientiam-remoteops")
SSH_KEY = os.environ.get("SROF_THINKPAD_KEY", "/run/secrets/thinkpad_key")
KNOWN_HOSTS = os.environ.get("SROF_KNOWN_HOSTS", "/run/secrets/known_hosts")

ALLOWED_REPO_ROOT = "/home/impejj/work/profesys"
SCIENTIAM_REPO = "/home/impejj/work/profesys/scientiam"
WORKER_SOURCE = os.environ.get("SROF_WORKER_SOURCE", "/source/srof-portable-worker")
SERVER_READ_WORKER_URL = os.environ.get("SROF_SERVER_READ_WORKER_URL", "http://srof-worker-read-server:8781").rstrip("/")
SERVER_READ_WORKER_TOKEN_FILE = os.environ.get("SROF_SERVER_READ_WORKER_TOKEN_FILE", "/run/secrets/server_read_worker_token")
SERVER_READ_OPERATIONS = ("fs_list", "fs_read", "fs_find", "git_status", "git_diff")
SERVER_DEV_WORKER_URL = os.environ.get("SROF_SERVER_DEV_WORKER_URL", "http://srof-worker-dev-server:8782").rstrip("/")
SERVER_DEV_WORKER_TOKEN_FILE = os.environ.get("SROF_SERVER_DEV_WORKER_TOKEN_FILE", "/run/secrets/server_dev_worker_token")
SERVER_DEV_TEST_PROFILES = ("srof-relay-tests",)
PATH_RE = re.compile(r"^/[A-Za-z0-9_./@+-]{1,500}$")
SCHEMA = "srof.relay.request.v1"


def ensure_storage() -> None:
    os.makedirs(RECEIPTS_DIR, exist_ok=True)


def db() -> sqlite3.Connection:
    ensure_storage()
    conn = sqlite3.connect(DB_PATH, timeout=30)
    conn.execute("PRAGMA journal_mode=WAL")
    conn.execute(
        """
        CREATE TABLE IF NOT EXISTS jobs (
            job_id TEXT PRIMARY KEY,
            request_json TEXT NOT NULL,
            state TEXT NOT NULL,
            result_json TEXT,
            created_at REAL NOT NULL,
            updated_at REAL NOT NULL
        )
        """
    )
    conn.commit()
    return conn


def set_state(job_id: str, state: str, result: dict | None = None) -> None:
    now = time.time()
    payload = json.dumps(result, sort_keys=True) if result is not None else None
    with db() as conn:
        conn.execute(
            "UPDATE jobs SET state=?, result_json=?, updated_at=? WHERE job_id=?",
            (state, payload, now, job_id),
        )
        conn.commit()


def validate_repo(path: str) -> str:
    if not isinstance(path, str) or not PATH_RE.fullmatch(path):
        raise ValueError("REPOSITORY_PATH_DENIED")
    p = PurePosixPath(path)
    if ".." in p.parts:
        raise ValueError("REPOSITORY_PATH_DENIED")
    if not (path == ALLOWED_REPO_ROOT or path.startswith(ALLOWED_REPO_ROOT + "/")):
        raise ValueError("REPOSITORY_OUTSIDE_ALLOWED_ROOT")
    lowered = {part.lower() for part in p.parts}
    if lowered & {".ssh", ".gnupg", ".secrets", "keys", "secrets", ".aws"}:
        raise ValueError("SENSITIVE_PATH_DENIED")
    return path


def ssh(argv: list[str], timeout: int = 30) -> dict:
    remote = " ".join(shlex.quote(x) for x in argv)
    cmd = [
        "ssh",
        "-i", SSH_KEY,
        "-o", "BatchMode=yes",
        "-o", "PasswordAuthentication=no",
        "-o", "ConnectTimeout=5",
        "-o", "StrictHostKeyChecking=yes",
        "-o", f"UserKnownHostsFile={KNOWN_HOSTS}",
        f"{THINKPAD_USER}@{THINKPAD_HOST}",
        remote,
    ]
    p = subprocess.run(cmd, text=True, capture_output=True, timeout=timeout, check=False)
    return {
        "exit_code": p.returncode,
        "stdout": p.stdout[-24000:],
        "stderr": p.stderr[-8000:],
    }


def scp_tree(local_path: str, remote_parent: str, timeout: int = 120) -> dict:
    if os.path.realpath(local_path) != os.path.realpath(WORKER_SOURCE):
        raise ValueError("WORKER_SOURCE_DENIED")
    if not os.path.isdir(local_path):
        raise FileNotFoundError("WORKER_SOURCE_UNAVAILABLE")
    cmd = [
        "scp",
        "-r",
        "-i", SSH_KEY,
        "-o", "BatchMode=yes",
        "-o", "PasswordAuthentication=no",
        "-o", "ConnectTimeout=5",
        "-o", "StrictHostKeyChecking=yes",
        "-o", f"UserKnownHostsFile={KNOWN_HOSTS}",
        local_path,
        f"{THINKPAD_USER}@{THINKPAD_HOST}:{remote_parent}/",
    ]
    p = subprocess.run(cmd, text=True, capture_output=True, timeout=timeout, check=False)
    return {
        "exit_code": p.returncode,
        "stdout": p.stdout[-8000:],
        "stderr": p.stderr[-8000:],
    }


def stage_worker_source(kind: str) -> str:
    if kind not in {"read", "dev"}:
        raise ValueError("WORKER_STAGE_KIND_DENIED")
    remote_root = f"/tmp/srof-portable-{kind}-{uuid.uuid4().hex}"
    created = ssh(["mkdir", "-m", "700", "-p", remote_root], 20)
    if created["exit_code"] != 0:
        raise RuntimeError(f"WORKER_STAGE_MKDIR_FAILED:{created['stderr'][-1000:]}")
    copied = scp_tree(WORKER_SOURCE, remote_root, 120)
    if copied["exit_code"] != 0:
        ssh(["rm", "-rf", remote_root], 20)
        raise RuntimeError(f"WORKER_STAGE_COPY_FAILED:{copied['stderr'][-1000:]}")
    return remote_root


def server_read_worker_request(method: str, endpoint: str, payload: dict | None = None) -> dict:
    if method not in {"GET", "POST"}:
        raise ValueError("WORKER_HTTP_METHOD_DENIED")
    if endpoint not in {"/health", "/capabilities", "/jobs"}:
        raise ValueError("WORKER_HTTP_ENDPOINT_DENIED")
    headers = {"Accept": "application/json"}
    data = None
    if method == "POST":
        if endpoint != "/jobs":
            raise ValueError("WORKER_HTTP_POST_DENIED")
        with open(SERVER_READ_WORKER_TOKEN_FILE, encoding="utf-8") as handle:
            token = handle.read().strip()
        if not token:
            raise RuntimeError("SERVER_READ_WORKER_TOKEN_EMPTY")
        headers["Authorization"] = "Bearer " + token
        headers["Content-Type"] = "application/json"
        data = json.dumps(payload or {}, sort_keys=True, separators=(",", ":")).encode("utf-8")
    req = Request(SERVER_READ_WORKER_URL + endpoint, data=data, headers=headers, method=method)
    try:
        with urlopen(req, timeout=20) as response:
            body = response.read(262144).decode("utf-8", "replace")
            return {"exit_code": 0, "stdout": body, "stderr": ""}
    except HTTPError as exc:
        body = exc.read(262144).decode("utf-8", "replace")
        return {"exit_code": 72, "stdout": body, "stderr": f"WORKER_HTTP_{exc.code}"}
    except Exception as exc:
        return {"exit_code": 73, "stdout": "", "stderr": f"WORKER_HTTP_FAILED:{type(exc).__name__}"}


def server_dev_worker_request(method: str, endpoint: str, payload: dict | None = None) -> dict:
    if method not in {"GET", "POST"}:
        raise ValueError("DEV_WORKER_HTTP_METHOD_DENIED")
    if endpoint not in {"/health", "/capabilities", "/jobs"}:
        raise ValueError("DEV_WORKER_HTTP_ENDPOINT_DENIED")
    headers = {"Accept": "application/json"}
    data = None
    if method == "POST":
        if endpoint != "/jobs":
            raise ValueError("DEV_WORKER_HTTP_POST_DENIED")
        with open(SERVER_DEV_WORKER_TOKEN_FILE, encoding="utf-8") as handle:
            token = handle.read().strip()
        if not token:
            raise RuntimeError("SERVER_DEV_WORKER_TOKEN_EMPTY")
        headers["Authorization"] = "Bearer " + token
        headers["Content-Type"] = "application/json"
        data = json.dumps(payload or {}, sort_keys=True, separators=(",", ":")).encode("utf-8")
    req = Request(SERVER_DEV_WORKER_URL + endpoint, data=data, headers=headers, method=method)
    try:
        with urlopen(req, timeout=210) as response:
            body = response.read(1048576).decode("utf-8", "replace")
            return {"exit_code": 0, "stdout": body, "stderr": ""}
    except HTTPError as exc:
        body = exc.read(1048576).decode("utf-8", "replace")
        return {"exit_code": 72, "stdout": body, "stderr": f"DEV_WORKER_HTTP_{exc.code}"}
    except Exception as exc:
        return {"exit_code": 73, "stdout": "", "stderr": f"DEV_WORKER_HTTP_FAILED:{type(exc).__name__}"}


def execute(req: dict) -> dict:
    if req.get("schema") != SCHEMA:
        raise ValueError("INVALID_SCHEMA")
    host_id = req.get("host_id")
    op = req.get("operation")
    args = req.get("args") or {}
    if not isinstance(args, dict):
        raise ValueError("ARGS_MUST_BE_OBJECT")

    if host_id == "PROFESYS-SCIENTIAM":
        if op == "server_read_worker_health":
            return server_read_worker_request("GET", "/health")
        if op == "server_read_worker_capabilities":
            return server_read_worker_request("GET", "/capabilities")
        if op == "server_read_worker_job":
            operation = str(args.get("operation", ""))
            job_args = args.get("args") or {}
            if operation not in SERVER_READ_OPERATIONS:
                raise ValueError("SERVER_READ_OPERATION_DENIED")
            if not isinstance(job_args, dict):
                raise ValueError("SERVER_READ_JOB_ARGS_MUST_BE_OBJECT")
            payload = {
                "schema": "srof.worker.job.v1",
                "request_id": "SROF-SERVER-READ-" + uuid.uuid4().hex[:20],
                "operation": operation,
                "args": job_args,
            }
            return server_read_worker_request("POST", "/jobs", payload)
        if op == "server_dev_worker_health":
            return server_dev_worker_request("GET", "/health")
        if op == "server_dev_worker_capabilities":
            return server_dev_worker_request("GET", "/capabilities")
        if op == "server_dev_worker_job":
            patch = args.get("patch")
            if not isinstance(patch, str) or not patch:
                raise ValueError("SERVER_DEV_PATCH_REQUIRED")
            profile = str(args.get("test_profile", "srof-relay-tests"))
            if profile not in SERVER_DEV_TEST_PROFILES:
                raise ValueError("SERVER_DEV_TEST_PROFILE_DENIED")
            base_ref = str(args.get("base_ref", "HEAD"))
            payload = {
                "schema": "srof.dev.job.v1",
                "request_id": "SROF-SERVER-DEV-" + uuid.uuid4().hex[:20],
                "operation": "candidate_patch",
                "args": {
                    "source_repo_path": ".",
                    "base_ref": base_ref,
                    "patch": patch,
                    "test_profile": profile,
                    "retain_workspace": False,
                },
            }
            return server_dev_worker_request("POST", "/jobs", payload)
        raise ValueError("SERVER_OPERATION_DENIED")

    if host_id != "THINKPAD-E470":
        raise ValueError("POC_HOST_DENIED")

    if op == "host_health":
        return ssh(["sh", "-lc", "hostname -s; id -un; uptime; df -P / | tail -1"], 20)

    if op == "git_status":
        repo = validate_repo(args.get("repository", ""))
        return ssh(["git", "-C", repo, "status", "--short", "--branch"], 25)

    if op == "fase0_probe":
        repo = SCIENTIAM_REPO
        script = """
set -e
cd /home/impejj/work/profesys/scientiam
echo "=== SROF FASE0 WORKER PROBE ==="
echo "HOST=$(hostname -s)"
echo "USER=$(id -un)"
echo "HEAD=$(git rev-parse --short HEAD)"
echo "=== REQUIRED FILES ==="
for f in \
  services/agent-control-plane/app/work_generation/contracts.py \
  services/agent-control-plane/app/work_generation/engine.py \
  services/agent-control-plane/app/software_factory/worker.py \
  tools/agent_governance/agent_governance/technical_resolver.py \
  docs/20_standards/worker-certification/STD-SC-WORKER-CERTIFICATION-001.md \
  platform/infrastructure/docker/stacks/scientiam-prefect-dev/docker-compose.yml
do
  test -f "$f"
  echo "PRESENT=$f"
done
echo "=== TESTS ==="
python3 -m pytest -q \
  services/agent-control-plane/tests/test_work_generation_engine.py \
  services/agent-control-plane/tests/test_software_factory_worker.py \
  tools/worker_certification/test_worker_certification.py \
  tools/agent_governance/tests/test_technical_resolver.py
echo "SROF_FASE0_PROBE=PASS"
"""
        return ssh(["bash", "-lc", script], 180)

    if op == "container_runtime_probe":
        # Read-only capability probe. Never changes groups, sockets, contexts or daemons.
        script = r"""
set +e
echo "HOST=$(hostname -s)"
echo "USER=$(id -un)"
echo "=== ID ==="
id
echo "=== SYSTEM DOCKER SOCKET ==="
if [ -S /var/run/docker.sock ]; then
  stat -c 'PATH=%n MODE=%A UID=%u GID=%g OWNER=%U GROUP=%G' /var/run/docker.sock
else
  echo "SYSTEM_DOCKER_SOCKET=ABSENT"
fi
echo "=== USER RUNTIME SOCKETS ==="
uid="$(id -u)"
for p in "/run/user/$uid/docker.sock" "/run/user/$uid/podman/podman.sock"; do
  if [ -S "$p" ]; then
    stat -c 'PATH=%n MODE=%A UID=%u GID=%g OWNER=%U GROUP=%G' "$p"
  else
    echo "ABSENT=$p"
  fi
done
echo "=== DOCKER CLI ==="
command -v docker || true
docker context show 2>&1 || true
docker version --format 'CLIENT={{.Client.Version}} SERVER={{.Server.Version}}' 2>&1 || true
echo "=== PODMAN CLI ==="
command -v podman || true
podman info --format 'HOST={{.Host.Hostname}} ROOTLESS={{.Host.Security.Rootless}}' 2>&1 || true
"""
        return ssh(["bash", "-lc", script], 30)

    if op == "portable_read_smoke":
        # Source is staged from the SERVER-owned canonical snapshot.
        # No GitHub fetch and no human checkout mutation occur on THINKPAD.
        remote_root = stage_worker_source("read")
        worker_dir = remote_root + "/srof-portable-worker"
        script = f"""
set -euo pipefail
ROOT={shlex.quote(remote_root)}
WORKER={shlex.quote(worker_dir)}
cleanup() {{
  docker compose -f "$WORKER/docker-compose.yml" down -v --remove-orphans >/dev/null 2>&1 || true
  rm -rf "$ROOT"
}}
trap cleanup EXIT

cd "$WORKER"
export SROF_WORKER_TOKEN="srof-relay-smoke-token"
export SROF_READ_ROOT="$PWD/fixture"
export SROF_RECEIPT_DIR="$PWD/.smoke-receipts"
bash ./scripts/smoke.sh

test -s "$SROF_RECEIPT_DIR/portable-read-smoke-001.json"
echo "SROF_PORTABLE_READ_HOST_SMOKE=PASS"
"""
        return ssh(["bash", "-lc", script], 300)

    if op == "portable_dev_smoke":
        # DEV uses the same staged source snapshot and keeps its own disposable
        # source/workspace lifecycle inside the remote temporary directory.
        remote_root = stage_worker_source("dev")
        worker_dir = remote_root + "/srof-portable-worker"
        script = f"""
set -euo pipefail
ROOT={shlex.quote(remote_root)}
WORKER={shlex.quote(worker_dir)}
cleanup() {{
  docker compose -f "$WORKER/docker-compose.dev.yml" down -v --remove-orphans >/dev/null 2>&1 || true
  rm -rf "$ROOT"
}}
trap cleanup EXIT

cd "$WORKER"
export SROF_WORKER_TOKEN="srof-relay-dev-smoke-token"
bash ./scripts/smoke-dev.sh

test -s "$PWD/.dev-smoke-receipts/portable-dev-smoke-001.json"
echo "SROF_PORTABLE_DEV_HOST_SMOKE=PASS"
"""
        return ssh(["bash", "-lc", script], 360)

    raise ValueError(f"OPERATION_DENIED:{op}")


def worker(job_id: str, req: dict) -> None:
    ensure_storage()
    set_state(job_id, "RUNNING")
    started = time.time()
    receipt = {
        "schema": "srof.relay.receipt.v1",
        "job_id": job_id,
        "request": req,
        "started_at": started,
        "worker": "srof-relay-docker-poc",
        "transport_execution": "LOCAL_RELAY",
        "dcp_used": False,
        "github_actions_executes_machine_command": False,
    }
    try:
        result = execute(req)
        receipt["execution"] = result
        receipt["ok"] = result["exit_code"] == 0
        receipt["state"] = "VERIFIED" if receipt["ok"] else "FAILED"
    except Exception as exc:
        receipt["ok"] = False
        receipt["state"] = "REJECTED"
        receipt["error"] = f"{type(exc).__name__}: {exc}"
    receipt["finished_at"] = time.time()

    canonical = json.dumps(receipt, sort_keys=True, separators=(",", ":")).encode()
    receipt["sha256"] = hashlib.sha256(canonical).hexdigest()

    path = os.path.join(RECEIPTS_DIR, f"{job_id}.json")
    with open(path, "w", encoding="utf-8") as f:
        json.dump(receipt, f, indent=2)
        f.write("\n")

    set_state(job_id, receipt["state"], receipt)


class Handler(BaseHTTPRequestHandler):
    server_version = "SROFRelay/0.1"

    def log_message(self, fmt: str, *args) -> None:
        print(f"{self.address_string()} - {fmt % args}", flush=True)

    def send_json(self, status: int, payload: dict) -> None:
        body = json.dumps(payload, indent=2).encode()
        self.send_response(status)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def do_GET(self) -> None:
        path = urlparse(self.path).path
        if path == "/health":
            self.send_json(200, {
                "state": "READY",
                "service": "srof-relay-poc",
                "worker": "docker",
                "target": "THINKPAD-E470",
                "operations": ["host_health", "git_status", "fase0_probe", "container_runtime_probe", "portable_read_smoke", "portable_dev_smoke", "server_read_worker_health", "server_read_worker_capabilities", "server_read_worker_job", "server_dev_worker_health", "server_dev_worker_capabilities", "server_dev_worker_job"],
            })
            return

        if path.startswith("/v1/jobs/"):
            job_id = path.split("/")[-1]
            with db() as conn:
                row = conn.execute(
                    "SELECT job_id,state,result_json,created_at,updated_at FROM jobs WHERE job_id=?",
                    (job_id,),
                ).fetchone()
            if not row:
                self.send_json(404, {"error": "JOB_NOT_FOUND"})
                return
            result = json.loads(row[2]) if row[2] else None
            self.send_json(200, {
                "job_id": row[0],
                "state": row[1],
                "result": result,
                "created_at": row[3],
                "updated_at": row[4],
            })
            return

        self.send_json(404, {"error": "NOT_FOUND"})

    def do_POST(self) -> None:
        path = urlparse(self.path).path
        if path != "/v1/jobs":
            self.send_json(404, {"error": "NOT_FOUND"})
            return

        try:
            length = int(self.headers.get("Content-Length", "0"))
            if length <= 0 or length > 65536:
                raise ValueError("INVALID_CONTENT_LENGTH")
            req = json.loads(self.rfile.read(length))
            if not isinstance(req, dict):
                raise ValueError("REQUEST_MUST_BE_OBJECT")
            if req.get("schema") != SCHEMA:
                raise ValueError("INVALID_SCHEMA")
            job_id = req.get("request_id") or f"SROF-JOB-{uuid.uuid4()}"
            now = time.time()
            with db() as conn:
                conn.execute(
                    "INSERT INTO jobs(job_id,request_json,state,created_at,updated_at) VALUES(?,?,?,?,?)",
                    (job_id, json.dumps(req, sort_keys=True), "QUEUED", now, now),
                )
                conn.commit()
            threading.Thread(target=worker, args=(job_id, req), daemon=True).start()
            self.send_json(202, {"job_id": job_id, "state": "QUEUED"})
        except sqlite3.IntegrityError:
            self.send_json(409, {"error": "DUPLICATE_REQUEST_ID"})
        except Exception as exc:
            self.send_json(400, {"error": f"{type(exc).__name__}: {exc}"})


def main() -> None:
    with db():
        pass
    print(f"SROF_RELAY_READY host={LISTEN_HOST} port={LISTEN_PORT}", flush=True)
    ThreadingHTTPServer((LISTEN_HOST, LISTEN_PORT), Handler).serve_forever()


if __name__ == "__main__":
    main()
