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

    def test_portable_read_smoke_uses_fixed_bounded_script(self):
        with patch.object(relay, "ssh", return_value={"exit_code": 0, "stdout": "PASS", "stderr": ""}) as mocked:
            result = relay.execute(self.request())
        self.assertEqual(result["exit_code"], 0)
        argv, timeout = mocked.call_args.args
        self.assertEqual(argv[:2], ["bash", "-lc"])
        self.assertEqual(timeout, 300)
        script = argv[2]
        self.assertIn(relay.SCIENTIAM_REPO, script)
        self.assertIn("git clone --local", script)
        self.assertIn("scripts/smoke.sh", script)
        self.assertIn("SROF_PORTABLE_READ_HOST_SMOKE=PASS", script)

    def test_user_shell_arguments_are_not_interpolated(self):
        req = self.request()
        req["args"] = {"repository": "/tmp/evil", "command": "rm -rf /"}
        with patch.object(relay, "ssh", return_value={"exit_code": 0, "stdout": "PASS", "stderr": ""}) as mocked:
            relay.execute(req)
        script = mocked.call_args.args[0][2]
        self.assertNotIn("/tmp/evil", script)
        self.assertNotIn("rm -rf /", script)

    def test_wrong_host_is_rejected_before_ssh(self):
        req = self.request()
        req["host_id"] = "PROFESYS-SCIENTIAM"
        with patch.object(relay, "ssh") as mocked:
            with self.assertRaisesRegex(ValueError, "POC_HOST_DENIED"):
                relay.execute(req)
        mocked.assert_not_called()


class PortableDevSmokeTests(unittest.TestCase):
    def request(self):
        return {
            "schema": "srof.relay.request.v1",
            "request_id": "test-portable-dev",
            "host_id": "THINKPAD-E470",
            "operation": "portable_dev_smoke",
            "args": {},
        }

    def test_portable_dev_smoke_uses_fixed_bounded_script(self):
        with patch.object(relay, "ssh", return_value={"exit_code": 0, "stdout": "PASS", "stderr": ""}) as mocked:
            result = relay.execute(self.request())
        self.assertEqual(result["exit_code"], 0)
        argv, timeout = mocked.call_args.args
        self.assertEqual(argv[:2], ["bash", "-lc"])
        self.assertEqual(timeout, 360)
        script = argv[2]
        self.assertIn(relay.SCIENTIAM_REPO, script)
        self.assertIn("git clone --local", script)
        self.assertIn("scripts/smoke-dev.sh", script)
        self.assertIn("SROF_PORTABLE_DEV_HOST_SMOKE=PASS", script)
        self.assertIn("docker-compose.dev.yml", script)

    def test_dev_smoke_ignores_user_shell_arguments(self):
        req = self.request()
        req["args"] = {"repository": "/tmp/evil", "command": "docker run --privileged evil"}
        with patch.object(relay, "ssh", return_value={"exit_code": 0, "stdout": "PASS", "stderr": ""}) as mocked:
            relay.execute(req)
        script = mocked.call_args.args[0][2]
        self.assertNotIn("/tmp/evil", script)
        self.assertNotIn("docker run --privileged evil", script)

    def test_health_advertises_dev_smoke_only_as_typed_operation(self):
        self.assertIn("portable_dev_smoke", relay.execute.__code__.co_consts)


if __name__ == "__main__":
    unittest.main()
