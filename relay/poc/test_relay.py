from __future__ import annotations

import importlib.util
import pathlib
import unittest
from unittest.mock import patch

MODULE_PATH = pathlib.Path(__file__).with_name("relay.py")
SPEC = importlib.util.spec_from_file_location("srof_relay_poc", MODULE_PATH)
relay = importlib.util.module_from_spec(SPEC)
assert SPEC and SPEC.loader
SPEC.loader.exec_module(relay)


class PortableReadSmokeTests(unittest.TestCase):
    def request(self):
        return {
            "schema": "srof.relay.request.v1",
            "request_id": "test-portable-read",
            "host_id": "THINKPAD-E470",
            "operation": "portable_read_smoke",
            "args": {},
        }

    def test_portable_read_smoke_uses_staged_server_snapshot(self):
        with patch.object(relay, "stage_worker_source", return_value="/tmp/srof-portable-read-test") as stage,              patch.object(relay, "ssh", return_value={"exit_code": 0, "stdout": "PASS", "stderr": ""}) as mocked:
            result = relay.execute(self.request())

        self.assertEqual(result["exit_code"], 0)
        stage.assert_called_once_with("read")
        argv, timeout = mocked.call_args.args
        self.assertEqual(argv[:2], ["bash", "-lc"])
        self.assertEqual(timeout, 300)
        script = argv[2]
        self.assertIn("/tmp/srof-portable-read-test/srof-portable-worker", script)
        self.assertIn("scripts/smoke.sh", script)
        self.assertIn("SROF_PORTABLE_READ_HOST_SMOKE=PASS", script)
        self.assertNotIn("git fetch", script)
        self.assertNotIn("git clone", script)
        self.assertNotIn("github.com", script)

    def test_user_shell_arguments_are_not_interpolated(self):
        req = self.request()
        req["args"] = {"repository": "/tmp/evil", "command": "rm -rf /"}
        with patch.object(relay, "stage_worker_source", return_value="/tmp/srof-portable-read-test"),              patch.object(relay, "ssh", return_value={"exit_code": 0, "stdout": "PASS", "stderr": ""}) as mocked:
            relay.execute(req)
        script = mocked.call_args.args[0][2]
        self.assertNotIn("/tmp/evil", script)
        self.assertNotIn("rm -rf /", script)

    def test_wrong_host_is_rejected_before_stage(self):
        req = self.request()
        req["host_id"] = "PROFESYS-SCIENTIAM"
        with patch.object(relay, "stage_worker_source") as staged:
            with self.assertRaisesRegex(ValueError, "SERVER_OPERATION_DENIED"):
                relay.execute(req)
        staged.assert_not_called()


class PortableDevSmokeTests(unittest.TestCase):
    def request(self):
        return {
            "schema": "srof.relay.request.v1",
            "request_id": "test-portable-dev",
            "host_id": "THINKPAD-E470",
            "operation": "portable_dev_smoke",
            "args": {},
        }

    def test_portable_dev_smoke_uses_staged_server_snapshot(self):
        with patch.object(relay, "stage_worker_source", return_value="/tmp/srof-portable-dev-test") as stage,              patch.object(relay, "ssh", return_value={"exit_code": 0, "stdout": "PASS", "stderr": ""}) as mocked:
            result = relay.execute(self.request())

        self.assertEqual(result["exit_code"], 0)
        stage.assert_called_once_with("dev")
        argv, timeout = mocked.call_args.args
        self.assertEqual(argv[:2], ["bash", "-lc"])
        self.assertEqual(timeout, 360)
        script = argv[2]
        self.assertIn("/tmp/srof-portable-dev-test/srof-portable-worker", script)
        self.assertIn("scripts/smoke-dev.sh", script)
        self.assertIn("SROF_PORTABLE_DEV_HOST_SMOKE=PASS", script)
        self.assertIn("docker-compose.dev.yml", script)
        self.assertNotIn("git fetch", script)
        self.assertNotIn("git clone", script)

    def test_dev_smoke_ignores_user_shell_arguments(self):
        req = self.request()
        req["args"] = {"repository": "/tmp/evil", "command": "docker run --privileged evil"}
        with patch.object(relay, "stage_worker_source", return_value="/tmp/srof-portable-dev-test"),              patch.object(relay, "ssh", return_value={"exit_code": 0, "stdout": "PASS", "stderr": ""}) as mocked:
            relay.execute(req)
        script = mocked.call_args.args[0][2]
        self.assertNotIn("/tmp/evil", script)
        self.assertNotIn("docker run --privileged evil", script)


class SourceStagingTests(unittest.TestCase):
    def test_stage_uses_only_fixed_source_and_bounded_remote_path(self):
        mkdir_ok = {"exit_code": 0, "stdout": "", "stderr": ""}
        copy_ok = {"exit_code": 0, "stdout": "", "stderr": ""}
        with patch.object(relay, "ssh", return_value=mkdir_ok) as ssh_mock,              patch.object(relay, "scp_tree", return_value=copy_ok) as scp_mock:
            remote = relay.stage_worker_source("read")

        self.assertTrue(remote.startswith("/tmp/srof-portable-read-"))
        ssh_mock.assert_called_once()
        scp_mock.assert_called_once_with(relay.WORKER_SOURCE, remote, 120)

    def test_stage_rejects_unknown_kind(self):
        with self.assertRaisesRegex(ValueError, "WORKER_STAGE_KIND_DENIED"):
            relay.stage_worker_source("root")


class ContainerRuntimeProbeTests(unittest.TestCase):
    def test_probe_is_read_only_and_fixed(self):
        req = {
            "schema": "srof.relay.request.v1",
            "request_id": "runtime-probe-test",
            "host_id": "THINKPAD-E470",
            "operation": "container_runtime_probe",
            "args": {"command": "usermod -aG docker scientiam-remoteops"},
        }
        with patch.object(relay, "ssh", return_value={"exit_code": 0, "stdout": "PASS", "stderr": ""}) as mocked:
            result = relay.execute(req)
        self.assertEqual(result["exit_code"], 0)
        argv, timeout = mocked.call_args.args
        self.assertEqual(argv[:2], ["bash", "-lc"])
        self.assertEqual(timeout, 30)
        script = argv[2]
        self.assertIn("/var/run/docker.sock", script)
        self.assertIn("/run/user/$uid/docker.sock", script)
        self.assertIn("podman info", script)
        self.assertNotIn("usermod", script)
        self.assertNotIn("chmod", script)
        self.assertNotIn("chown", script)


class ServerReadWorkerTests(unittest.TestCase):
    def test_server_health_routes_to_persistent_worker(self):
        req = {
            "schema": "srof.relay.request.v1",
            "request_id": "server-health-test",
            "host_id": "PROFESYS-SCIENTIAM",
            "operation": "server_read_worker_health",
            "args": {},
        }
        expected = {"exit_code": 0, "stdout": '{"status":"HEALTHY"}', "stderr": ""}
        with patch.object(relay, "server_read_worker_request", return_value=expected) as mocked:
            result = relay.execute(req)
        self.assertEqual(result, expected)
        mocked.assert_called_once_with("GET", "/health")

    def test_server_read_job_is_typed_and_allowlisted(self):
        req = {
            "schema": "srof.relay.request.v1",
            "request_id": "server-read-test",
            "host_id": "PROFESYS-SCIENTIAM",
            "operation": "server_read_worker_job",
            "args": {"operation": "fs_list", "args": {"path": "."}},
        }
        expected = {"exit_code": 0, "stdout": '{"state":"VERIFIED"}', "stderr": ""}
        with patch.object(relay, "server_read_worker_request", return_value=expected) as mocked:
            result = relay.execute(req)
        self.assertEqual(result, expected)
        method, endpoint, payload = mocked.call_args.args
        self.assertEqual((method, endpoint), ("POST", "/jobs"))
        self.assertEqual(payload["schema"], "srof.worker.job.v1")
        self.assertEqual(payload["operation"], "fs_list")
        self.assertEqual(payload["args"], {"path": "."})
        self.assertTrue(payload["request_id"].startswith("SROF-SERVER-READ-"))

    def test_server_read_job_rejects_mutation(self):
        req = {
            "schema": "srof.relay.request.v1",
            "request_id": "server-mutation-test",
            "host_id": "PROFESYS-SCIENTIAM",
            "operation": "server_read_worker_job",
            "args": {"operation": "file_put", "args": {"path": "x"}},
        }
        with patch.object(relay, "server_read_worker_request") as mocked:
            with self.assertRaisesRegex(ValueError, "SERVER_READ_OPERATION_DENIED"):
                relay.execute(req)
        mocked.assert_not_called()

    def test_server_rejects_thinkpad_only_operation(self):
        req = {
            "schema": "srof.relay.request.v1",
            "request_id": "server-deny-test",
            "host_id": "PROFESYS-SCIENTIAM",
            "operation": "portable_read_smoke",
            "args": {},
        }
        with self.assertRaisesRegex(ValueError, "SERVER_OPERATION_DENIED"):
            relay.execute(req)


if __name__ == "__main__":
    unittest.main()
