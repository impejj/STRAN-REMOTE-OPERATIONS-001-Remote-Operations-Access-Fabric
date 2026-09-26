from __future__ import annotations

import base64
import json

import pytest

from srof_gateway.worker_runtime import (
    DEV_WORKER_ID,
    READ_WORKER_ID,
    worker_capabilities_argv,
    worker_health_argv,
    worker_inventory,
    worker_read_job_argv,
    worker_spec,
)


def test_worker_inventory_is_typed_and_small():
    rows = worker_inventory()
    assert [row["worker_id"] for row in rows] == [READ_WORKER_ID, DEV_WORKER_ID]
    assert rows[0]["role"] == "READ"
    assert "fs_read" in rows[0]["operations"]
    assert rows[1]["role"] == "DEV"
    assert rows[1]["operations"] == []


def test_unknown_worker_fails_closed():
    with pytest.raises(PermissionError):
        worker_spec("SROF-WORKER-ROOT-999")


def test_health_and_capabilities_are_loopback_only():
    health = worker_health_argv(READ_WORKER_ID)
    caps = worker_capabilities_argv(DEV_WORKER_ID)
    assert "http://127.0.0.1:8781/health" in health
    assert "http://127.0.0.1:8782/capabilities" in caps
    assert not any("0.0.0.0" in item for item in health + caps)


def test_read_job_is_structured_and_secret_never_enters_argv():
    argv = worker_read_job_argv(
        READ_WORKER_ID,
        request_id="SROF-WRK-TEST-001",
        operation="fs_read",
        args={"path": "README.md"},
    )
    payload = json.loads(base64.b64decode(argv[-1]).decode("utf-8"))
    assert payload == {
        "schema": "srof.worker.job.v1",
        "request_id": "SROF-WRK-TEST-001",
        "operation": "fs_read",
        "args": {"path": "README.md"},
    }
    joined = " ".join(argv)
    # The helper may contain the HTTP scheme literal "Bearer ", but no secret
    # value is ever serialized into argv. The target host reads it at runtime
    # from the protected token file.
    assert "replace-with-runtime-secret" not in joined
    assert "ci-ephemeral-token" not in joined
    assert "/etc/scientiam/srof-workers/read.token" in joined
    assert "open(token_file" in joined


def test_read_job_rejects_mutation_and_dev_execution():
    with pytest.raises(PermissionError):
        worker_read_job_argv(
            READ_WORKER_ID,
            request_id="SROF-WRK-TEST-002",
            operation="file_put",
            args={"path": "x"},
        )

    with pytest.raises(PermissionError):
        worker_read_job_argv(
            DEV_WORKER_ID,
            request_id="SROF-WRK-TEST-003",
            operation="candidate_patch",
            args={},
        )
