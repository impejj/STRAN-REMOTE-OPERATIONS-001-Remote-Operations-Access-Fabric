import importlib.util
import pathlib
import unittest

MODULE_PATH = pathlib.Path(__file__).resolve().parents[1] / "srof_openai_client.py"
SPEC = importlib.util.spec_from_file_location("srof_openai_client", MODULE_PATH)
client = importlib.util.module_from_spec(SPEC)
assert SPEC.loader is not None
SPEC.loader.exec_module(client)


class ClientTests(unittest.TestCase):
    def test_pkce_challenge_matches_rfc7636(self):
        verifier = "dBjftJeZ4CVP-mB92K27uhbUJU1p1r_wW1gFWFOEjXk"
        self.assertEqual(
            client._pkce_challenge(verifier),
            "E9Melhoa2OwvFrEMTJguCHaoeK1t8URWbuGJSstw-cM",
        )

    def test_build_request_is_read_only_and_bound_to_srof(self):
        payload = client.build_request(
            prompt="probe",
            model="test-model",
            srof_url="https://srof.scientiam.com.ar/mcp",
            srof_access_token="token",
        )
        self.assertEqual(payload["model"], "test-model")
        self.assertEqual(len(payload["tools"]), 1)
        tool = payload["tools"][0]
        self.assertEqual(tool["type"], "mcp")
        self.assertEqual(tool["server_url"], "https://srof.scientiam.com.ar/mcp")
        self.assertEqual(tool["authorization"], "token")
        self.assertEqual(tool["require_approval"], "never")
        self.assertIn("hosts_list", tool["allowed_tools"])
        self.assertNotIn("shell", tool["allowed_tools"])

    def test_collect_mcp_events(self):
        response = {
            "id": "resp_1",
            "output": [
                {"type": "mcp_list_tools", "tools": [{"name": "hosts_list"}, {"name": "host_health"}]},
                {
                    "type": "mcp_call",
                    "name": "hosts_list",
                    "arguments": "{}",
                    "output": "[]",
                    "error": None,
                    "server_label": "scientiam_srof",
                },
                {
                    "type": "mcp_call",
                    "name": "host_health",
                    "arguments": "{\"host_id\":\"PROFESYS-SCIENTIAM\"}",
                    "output": "{\"ok\":true}",
                    "error": None,
                    "server_label": "scientiam_srof",
                },
                {
                    "type": "message",
                    "content": [{"type": "output_text", "text": "healthy"}],
                },
            ],
        }
        summary = client.collect_mcp_events(response)
        self.assertEqual(summary["response_id"], "resp_1")
        self.assertEqual(summary["discovered_tools"], ["host_health", "hosts_list"])
        self.assertEqual(summary["calls"][0]["name"], "hosts_list")
        self.assertEqual(summary["errors"], [])
        self.assertEqual(summary["output_text"], "healthy")
        self.assertEqual(
            client.called_host_health_targets(summary),
            {"PROFESYS-SCIENTIAM"},
        )


if __name__ == "__main__":
    unittest.main()
