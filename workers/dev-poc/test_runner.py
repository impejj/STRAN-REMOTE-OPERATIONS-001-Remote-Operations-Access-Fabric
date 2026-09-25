from __future__ import annotations

import json
from pathlib import Path
from unittest.mock import patch

import runner


def test_rejects_arbitrary_operation() -> None:
    try:
        runner.validate_job({
            "schema": "srof.worker.job.v0.1",
            "request_id": "x",
            "operation": "shell",
            "tests": ["services/agent-control-plane/tests/test_work_generation_engine.py"],
        })
    except runner.WorkerError as exc:
        assert "OPERATION_DENIED" in str(exc)
    else:
        raise AssertionError("expected operation denial")


def test_rejects_path_escape() -> None:
    try:
        runner.validate_job({
            "schema": "srof.worker.job.v0.1",
            "request_id": "x",
            "operation": "pytest_selected",
            "tests": ["../etc/passwd"],
        })
    except runner.WorkerError as exc:
        assert "unsafe relative path" in str(exc)
    else:
        raise AssertionError("expected path denial")


def test_accepts_wge_test_path() -> None:
    request_id, tests = runner.validate_job({
        "schema": "srof.worker.job.v0.1",
        "request_id": "probe",
        "operation": "pytest_selected",
        "tests": ["services/agent-control-plane/tests/test_work_generation_engine.py"],
    })
    assert request_id == "probe"
    assert tests == ["services/agent-control-plane/tests/test_work_generation_engine.py"]
