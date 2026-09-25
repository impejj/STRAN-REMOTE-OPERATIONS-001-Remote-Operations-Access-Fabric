#!/usr/bin/env python3
from __future__ import annotations

import json
import os
import shutil
import subprocess
import sys
import tempfile
from pathlib import Path, PurePosixPath

SCHEMA = "srof.worker.job.v0.1"
SOURCE_ROOT = Path(os.environ.get("SROF_SOURCE_ROOT", "/src"))
OUT_ROOT = Path(os.environ.get("SROF_OUT_ROOT", "/out"))

ALLOWED_TEST_PREFIXES = (
    "services/agent-control-plane/tests/",
    "tools/worker_certification/",
    "tools/agent_governance/tests/",
)


class WorkerError(RuntimeError):
    pass


def safe_relative(path: str) -> str:
    p = PurePosixPath(path)
    if p.is_absolute() or ".." in p.parts or not path.strip():
        raise WorkerError(f"unsafe relative path: {path!r}")
    return str(p)


def validate_job(job: dict) -> tuple[str, list[str]]:
    if job.get("schema") != SCHEMA:
        raise WorkerError("INVALID_SCHEMA")
    if job.get("operation") != "pytest_selected":
        raise WorkerError("OPERATION_DENIED")
    request_id = str(job.get("request_id", "")).strip()
    if not request_id:
        raise WorkerError("REQUEST_ID_REQUIRED")
    tests = job.get("tests")
    if not isinstance(tests, list) or not tests:
        raise WorkerError("TESTS_REQUIRED")
    normalized: list[str] = []
    for raw in tests:
        rel = safe_relative(str(raw))
        if not any(rel.startswith(prefix) for prefix in ALLOWED_TEST_PREFIXES):
            raise WorkerError(f"TEST_PATH_DENIED:{rel}")
        normalized.append(rel)
    return request_id, normalized


def copy_clean_snapshot(dst: Path) -> None:
    if not SOURCE_ROOT.is_dir():
        raise WorkerError("SOURCE_ROOT_MISSING")
    for entry in SOURCE_ROOT.iterdir():
        if entry.name in {".git", ".secrets", ".ssh", "keys", "secrets"}:
            continue
        target = dst / entry.name
        if entry.is_dir():
            shutil.copytree(entry, target, symlinks=False)
        elif entry.is_file():
            shutil.copy2(entry, target)


def main() -> int:
    try:
        job = json.load(sys.stdin)
        request_id, tests = validate_job(job)
        OUT_ROOT.mkdir(parents=True, exist_ok=True)
        with tempfile.TemporaryDirectory(prefix="srof-dev-worker-") as tmp:
            workspace = Path(tmp) / "workspace"
            workspace.mkdir()
            copy_clean_snapshot(workspace)

            missing = [path for path in tests if not (workspace / path).is_file()]
            if missing:
                raise WorkerError("MISSING_TEST_PATHS:" + ",".join(missing))

            cmd = [sys.executable, "-m", "pytest", "-q", *tests]
            proc = subprocess.run(
                cmd,
                cwd=workspace,
                text=True,
                capture_output=True,
                timeout=600,
                check=False,
            )
            result = {
                "schema": "srof.worker.result.v0.1",
                "request_id": request_id,
                "worker_profile": "PROFILE-DEV-WORKTREE",
                "operation": "pytest_selected",
                "tests": tests,
                "exit_code": proc.returncode,
                "stdout": proc.stdout[-24000:],
                "stderr": proc.stderr[-8000:],
                "workspace_ephemeral": True,
                "human_worktree_mutated": False,
                "ok": proc.returncode == 0,
            }
    except Exception as exc:
        result = {
            "schema": "srof.worker.result.v0.1",
            "request_id": None,
            "operation": "pytest_selected",
            "ok": False,
            "error": f"{type(exc).__name__}: {exc}",
            "workspace_ephemeral": True,
            "human_worktree_mutated": False,
        }

    out = OUT_ROOT / "result.json"
    out.write_text(json.dumps(result, indent=2) + "\n", encoding="utf-8")
    print(json.dumps(result, indent=2))
    return 0 if result.get("ok") else 1


if __name__ == "__main__":
    raise SystemExit(main())
