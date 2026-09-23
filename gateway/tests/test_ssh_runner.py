from pathlib import Path
from unittest.mock import Mock, patch

from srof_gateway.ssh_runner import SshRunner


@patch("srof_gateway.ssh_runner.subprocess.run")
def test_runner_builds_structured_ssh_command(mock_run, tmp_path: Path):
    mock_run.return_value = Mock(returncode=0, stdout="active\n", stderr="")
    runner = SshRunner(tmp_path)

    receipt = runner.run_argv(
        host_id="SERVER",
        ssh_alias="server",
        operation="service_status",
        remote_argv=["systemctl", "is-active", "--", "scientiam-example.service"],
    )

    command = mock_run.call_args.args[0]
    assert command[:5] == ["ssh", "-o", "BatchMode=yes", "--", "server"]
    assert "systemctl is-active -- scientiam-example.service" in command[5]
    assert receipt.exit_code == 0
    assert (tmp_path / f"{receipt.request_id}.json").is_file()


@patch("srof_gateway.ssh_runner.subprocess.run")
def test_receipt_bounds_output(mock_run, tmp_path: Path):
    mock_run.return_value = Mock(returncode=1, stdout="x" * 20000, stderr="e" * 12000)
    receipt = SshRunner(tmp_path).run_argv("SERVER", "server", "bounded", ["false"])
    assert len(receipt.stdout) == 16000
    assert len(receipt.stderr) == 8000


def test_constructor_has_no_filesystem_side_effect(tmp_path: Path):
    receipt_dir = tmp_path / "nested" / "receipts"
    SshRunner(receipt_dir)
    assert not receipt_dir.exists()


@patch("srof_gateway.ssh_runner.subprocess.run")
def test_receipt_dir_is_created_before_remote_execution(mock_run, tmp_path: Path):
    mock_run.return_value = Mock(returncode=0, stdout="ok\n", stderr="")
    receipt_dir = tmp_path / "nested" / "receipts"

    receipt = SshRunner(receipt_dir).run_argv(
        "SERVER",
        "server",
        "health",
        ["true"],
    )

    assert receipt_dir.is_dir()
    assert (receipt_dir / f"{receipt.request_id}.json").is_file()
