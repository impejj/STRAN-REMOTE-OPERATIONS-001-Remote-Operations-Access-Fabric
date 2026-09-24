from __future__ import annotations

import json
import os
import time
import traceback
import uuid
from datetime import datetime, timezone
from pathlib import Path
from typing import Any, Callable

from google.oauth2 import service_account
from googleapiclient.discovery import build

from . import server

SHEET_ID = os.environ["SROF_GAP_SHEET_ID"]
CREDENTIALS = os.environ["GOOGLE_APPLICATION_CREDENTIALS"]
POLL_SECONDS = max(5, int(os.environ.get("SROF_GAP_POLL_SECONDS", "15")))
LOCAL_RECEIPTS = Path(
    os.environ.get(
        "SROF_GAP_RECEIPT_DIR",
        "/var/lib/scientiam/remote-ops/gap-receipts",
    )
)

SCOPES = ["https://www.googleapis.com/auth/spreadsheets"]

REQUEST_COLUMNS = [
    "request_id",
    "created_at",
    "actor",
    "target_host",
    "operation",
    "args_json",
    "risk_class",
    "status",
    "claimed_at",
    "finished_at",
    "receipt_id",
    "result_summary",
    "error",
]

READ_ONLY_OPS: dict[str, Callable[..., Any]] = {
    "hosts_list": server.hosts_list,
    "host_health": server.host_health,
    "fs_list": server.fs_list,
    "fs_read": server.fs_read,
    "fs_find": server.fs_find,
    "process_list": server.process_list,
    "service_status": server.service_status,
    "docker_ps": server.docker_ps,
    "docker_logs": server.docker_logs,
    "git_status": server.git_status,
    "git_diff": server.git_diff,
    "journal_tail": server.journal_tail,
    "network_listeners": server.network_listeners,
}


def _now() -> str:
    return datetime.now(timezone.utc).isoformat(timespec="seconds")


def _sheets():
    creds = service_account.Credentials.from_service_account_file(
        CREDENTIALS,
        scopes=SCOPES,
    )
    return build("sheets", "v4", credentials=creds, cache_discovery=False)


def _request_rows(api) -> list[list[str]]:
    response = (
        api.spreadsheets()
        .values()
        .get(
            spreadsheetId=SHEET_ID,
            range="REQUESTS!A2:M",
            valueRenderOption="UNFORMATTED_VALUE",
        )
        .execute()
    )
    return response.get("values", [])


def _update_request(api, row_number: int, values: dict[str, str]) -> None:
    data = []
    for key, value in values.items():
        col = REQUEST_COLUMNS.index(key)
        letter = chr(ord("A") + col)
        data.append(
            {
                "range": f"REQUESTS!{letter}{row_number}",
                "values": [[value]],
            }
        )
    api.spreadsheets().values().batchUpdate(
        spreadsheetId=SHEET_ID,
        body={"valueInputOption": "RAW", "data": data},
    ).execute()


def _append_receipt(api, row: list[str]) -> None:
    api.spreadsheets().values().append(
        spreadsheetId=SHEET_ID,
        range="RECEIPTS!A:K",
        valueInputOption="RAW",
        insertDataOption="INSERT_ROWS",
        body={"values": [row]},
    ).execute()


def _bounded(value: Any, limit: int = 12000) -> str:
    text = json.dumps(value, ensure_ascii=False, sort_keys=True, default=str)
    if len(text) <= limit:
        return text
    return text[: limit - 32] + "...<TRUNCATED>"


def _execute(target_host: str, operation: str, args: dict[str, Any]) -> Any:
    if operation not in READ_ONLY_OPS:
        raise PermissionError(f"operation {operation!r} is not allowed by gap bridge")

    fn = READ_ONLY_OPS[operation]
    if operation == "hosts_list":
        if target_host:
            raise ValueError("hosts_list must not set target_host")
        return fn()

    if not target_host:
        raise ValueError(f"target_host is required for {operation}")

    return fn(target_host, **args)


def _receipt_id(result: Any) -> str:
    if isinstance(result, dict):
        receipt = result.get("receipt")
        if isinstance(receipt, dict) and receipt.get("request_id"):
            return str(receipt["request_id"])
    return f"GAP-{uuid.uuid4()}"


def process_once() -> int:
    api = _sheets()
    rows = _request_rows(api)
    processed = 0

    for offset, raw in enumerate(rows, start=2):
        padded = list(raw) + [""] * (len(REQUEST_COLUMNS) - len(raw))
        req = dict(zip(REQUEST_COLUMNS, padded))

        if str(req["status"]).strip().upper() != "PENDING":
            continue

        request_id = str(req["request_id"]).strip()
        if not request_id or request_id == "REQ-DEMO-DO-NOT-RUN":
            continue

        operation = str(req["operation"]).strip()
        target = str(req["target_host"]).strip()
        risk_class = str(req["risk_class"]).strip().upper()

        if risk_class not in {"READ_ONLY", "T0"}:
            _update_request(
                api,
                offset,
                {
                    "status": "DENIED",
                    "finished_at": _now(),
                    "error": "gap bridge accepts READ_ONLY/T0 only",
                },
            )
            processed += 1
            continue

        claimed = _now()
        _update_request(
            api,
            offset,
            {"status": "CLAIMED", "claimed_at": claimed},
        )

        started = _now()
        try:
            args = json.loads(str(req["args_json"] or "{}"))
            if not isinstance(args, dict):
                raise ValueError("args_json must decode to an object")

            result = _execute(target, operation, args)
            rid = _receipt_id(result)
            finished = _now()
            summary = _bounded(result)

            LOCAL_RECEIPTS.mkdir(parents=True, exist_ok=True)
            local_path = LOCAL_RECEIPTS / f"{request_id}.json"
            local_path.write_text(
                json.dumps(
                    {
                        "request_id": request_id,
                        "bridge": "SROF-GAP-BRIDGE-001",
                        "operation": operation,
                        "host_id": target,
                        "started_at": started,
                        "finished_at": finished,
                        "receipt_id": rid,
                        "result": result,
                    },
                    ensure_ascii=False,
                    indent=2,
                    default=str,
                )
                + "\n",
                encoding="utf-8",
            )

            exit_code = 0
            verification = "PASS"
            stdout = summary
            stderr = ""
            if isinstance(result, dict) and isinstance(result.get("receipt"), dict):
                rec = result["receipt"]
                exit_code = int(rec.get("exit_code", 0))
                stdout = str(rec.get("stdout", ""))[-12000:]
                stderr = str(rec.get("stderr", ""))[-4000:]
                verification = "PASS" if exit_code == 0 else "FAIL"

            _append_receipt(
                api,
                [
                    rid,
                    request_id,
                    started,
                    finished,
                    target,
                    operation,
                    str(exit_code),
                    verification,
                    stdout,
                    stderr,
                    str(local_path),
                ],
            )

            _update_request(
                api,
                offset,
                {
                    "status": "DONE" if exit_code == 0 else "FAILED",
                    "finished_at": finished,
                    "receipt_id": rid,
                    "result_summary": summary,
                    "error": stderr if exit_code else "",
                },
            )
        except Exception as exc:
            finished = _now()
            error = f"{type(exc).__name__}: {exc}"
            _append_receipt(
                api,
                [
                    f"GAP-{uuid.uuid4()}",
                    request_id,
                    started,
                    finished,
                    target,
                    operation,
                    "1",
                    "FAIL",
                    "",
                    error,
                    "",
                ],
            )
            _update_request(
                api,
                offset,
                {
                    "status": "FAILED",
                    "finished_at": finished,
                    "error": error,
                },
            )
        processed += 1

    return processed


def main() -> int:
    while True:
        try:
            process_once()
        except Exception:
            traceback.print_exc()
        time.sleep(POLL_SECONDS)


if __name__ == "__main__":
    raise SystemExit(main())
