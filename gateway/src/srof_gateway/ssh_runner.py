from __future__ import annotations

import hashlib
import json
import shlex
import subprocess
import time
import uuid
from dataclasses import asdict, dataclass
from pathlib import Path
from typing import Sequence

from mcp.server.auth.middleware.auth_context import get_access_token


@dataclass
class Receipt:
    request_id: str
    host_id: str
    operation: str
    started_at: float
    finished_at: float
    exit_code: int
    stdout: str
    stderr: str
    command_digest: str
    actor_subject: str | None = None
    client_id: str | None = None
    scopes: list[str] | None = None


class SshRunner:
    def __init__(self, receipt_dir: Path, timeout_seconds: int = 30) -> None:
        self.receipt_dir = receipt_dir
        self.timeout_seconds = timeout_seconds

    def run_argv(self, host_id: str, ssh_alias: str, operation: str, remote_argv: Sequence[str]) -> Receipt:
        # Receipt storage is mandatory but must not cause filesystem side
        # effects merely by importing the gateway module. Create/verify it
        # immediately before any remote operation so failure remains fail-closed.
        self.receipt_dir.mkdir(parents=True, exist_ok=True)

        request_id = f"SROF-{uuid.uuid4()}"
        started = time.time()

        # The caller supplies a structured argv assembled by gateway code.
        # shlex.join only serializes that fixed argv for OpenSSH's remote
        # command string; it does not turn database/user text into shell
        # authority.
        remote = shlex.join(list(remote_argv))
        command = ["ssh", "-o", "BatchMode=yes", "--", ssh_alias, remote]
        proc = subprocess.run(
            command,
            capture_output=True,
            text=True,
            timeout=self.timeout_seconds,
            check=False,
        )
        finished = time.time()

        # Receipts store a digest instead of the command itself to avoid
        # accidentally persisting sensitive command arguments.
        digest = hashlib.sha256(json.dumps(command, separators=(",", ":")).encode()).hexdigest()
        auth = get_access_token()
        receipt = Receipt(
            request_id=request_id,
            host_id=host_id,
            operation=operation,
            started_at=started,
            finished_at=finished,
            exit_code=proc.returncode,
            stdout=proc.stdout[-16000:],
            stderr=proc.stderr[-8000:],
            command_digest=digest,
            actor_subject=auth.subject if auth is not None else None,
            client_id=auth.client_id if auth is not None else None,
            scopes=list(auth.scopes) if auth is not None else None,
        )
        path = self.receipt_dir / f"{request_id}.json"
        path.write_text(json.dumps(asdict(receipt), indent=2, sort_keys=True) + "\n", encoding="utf-8")
        return receipt
