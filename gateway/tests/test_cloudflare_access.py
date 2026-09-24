from __future__ import annotations

import os
import unittest
from unittest.mock import patch

from srof_gateway.cloudflare_access import (
    CloudflareAccessConfig,
    CloudflareAccessVerifier,
    _header,
)


class CloudflareAccessConfigTests(unittest.TestCase):
    def test_disabled_does_not_require_account_values(self):
        with patch.dict(os.environ, {}, clear=True):
            config = CloudflareAccessConfig.from_env()
        self.assertFalse(config.required)
        self.assertEqual(config.team_domain, "")
        self.assertEqual(config.audience, "")

    def test_required_fails_closed_without_values(self):
        with patch.dict(os.environ, {"SROF_CF_ACCESS_REQUIRED": "1"}, clear=True):
            with self.assertRaises(RuntimeError):
                CloudflareAccessConfig.from_env()

    def test_required_builds_cloudflare_issuer_and_certs(self):
        env = {
            "SROF_CF_ACCESS_REQUIRED": "true",
            "SROF_CF_TEAM_DOMAIN": "profesys.cloudflareaccess.com",
            "SROF_CF_ACCESS_AUD": "aud-123",
        }
        with patch.dict(os.environ, env, clear=True):
            config = CloudflareAccessConfig.from_env()
        self.assertTrue(config.required)
        self.assertEqual(config.issuer, "https://profesys.cloudflareaccess.com")
        self.assertEqual(
            config.certs_url,
            "https://profesys.cloudflareaccess.com/cdn-cgi/access/certs",
        )

    @patch("srof_gateway.cloudflare_access.jwt.decode")
    @patch("srof_gateway.cloudflare_access.jwt.PyJWKClient")
    def test_verifier_checks_rs256_audience_and_issuer(self, jwks_cls, decode):
        config = CloudflareAccessConfig(
            team_domain="profesys.cloudflareaccess.com",
            audience="aud-123",
            required=True,
        )
        jwks_cls.return_value.get_signing_key_from_jwt.return_value.key = "PUBLIC"
        decode.return_value = {"sub": "founder@example.com", "aud": ["aud-123"]}

        claims = CloudflareAccessVerifier(config).verify("header.payload.signature")

        self.assertEqual(claims["sub"], "founder@example.com")
        decode.assert_called_once_with(
            "header.payload.signature",
            "PUBLIC",
            algorithms=["RS256"],
            audience="aud-123",
            issuer="https://profesys.cloudflareaccess.com",
        )

    def test_header_lookup_is_case_insensitive(self):
        scope = {
            "headers": [
                (b"host", b"127.0.0.1"),
                (b"Cf-Access-Jwt-Assertion".lower(), b"TOKEN"),
            ]
        }
        self.assertEqual(_header(scope, "Cf-Access-Jwt-Assertion"), "TOKEN")


if __name__ == "__main__":
    unittest.main(verbosity=2)
