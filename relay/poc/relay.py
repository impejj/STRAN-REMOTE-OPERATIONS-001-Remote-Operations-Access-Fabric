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
from urllib.parse import urlparse

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
PATH_RE = re.compile(r"^/[A-Za-z0-9_./@+-]{1,500}$")
SCHEMA = "srof.relay.request.v1"

os.makedirs(RECEIPTS_DIR, exist_ok=True)


def db() -> sqlite3.Connection:
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


def execute(req: dict) -> dict:
    if req.get("schema") != SCHEMA:
        raise ValueError("INVALID_SCHEMA")
    if req.get("host_id") != "THINKPAD-E470":
        raise ValueError("POC_HOST_DENIED")
    op = req.get("operation")
    args = req.get("args") or {}
    if not isinstance(args, dict):
        raise ValueError("ARGS_MUST_BE_OBJECT")

    if op == "host_health":
        return ssh(["sh", "-lc", "hostname -s; id -un; uptime; df -P / | tail -1"], 20)

    if op == "git_status":
        repo = validate_repo(args.get("repository", ""))
        return ssh(["git", "-C", repo, "status", "--short", "--branch"], 25)

    if op == "fase0_probe":
        repo = "/home/impejj/work/profesys/scientiam"
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

    raise ValueError(f"OPERATION_DENIED:{op}")


def worker(job_id: str, req: dict) -> None:
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
                "operations": ["host_health", "git_status", "fase0_probe"],
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
