from __future__ import annotations

import os
import unittest
from unittest.mock import patch

import jwt

from srof_gateway.keycloak_auth import KeycloakJWTVerifier, OAuthRuntimeConfig


class OAuthRuntimeConfigTests(unittest.TestCase):
    def test_disabled_has_safe_defaults(self):
        with patch.dict(os.environ, {}, clear=True):
            cfg = OAuthRuntimeConfig.from_env()
        self.assertFalse(cfg.required)

    def test_required_fails_closed_without_values(self):
        with patch.dict(os.environ, {"SROF_OAUTH_REQUIRED": "1"}, clear=True):
            with self.assertRaises(RuntimeError):
                OAuthRuntimeConfig.from_env()

    def test_required_builds_keycloak_jwks_url(self):
        env = {
            "SROF_OAUTH_REQUIRED": "1",
            "SROF_OAUTH_ISSUER": "https://auth.scientiam.com.ar/realms/scientiam-srof",
            "SROF_OAUTH_RESOURCE": "https://srof.scientiam.com.ar/mcp",
            "SROF_OAUTH_REQUIRED_SCOPES": "srof:read",
        }
        with patch.dict(os.environ, env, clear=True):
            cfg = OAuthRuntimeConfig.from_env()
        self.assertEqual(
            cfg.jwks_url,
            "https://auth.scientiam.com.ar/realms/scientiam-srof/protocol/openid-connect/certs",
        )


class KeycloakJWTVerifierTests(unittest.IsolatedAsyncioTestCase):
    def setUp(self):
        self.cfg = OAuthRuntimeConfig(
            required=True,
            issuer="https://auth.scientiam.com.ar/realms/scientiam-srof",
            resource="https://srof.scientiam.com.ar/mcp",
            required_scopes=("srof:read",),
            jwks_url="https://auth.scientiam.com.ar/realms/scientiam-srof/protocol/openid-connect/certs",
        )

    @patch("srof_gateway.keycloak_auth.jwt.decode")
    @patch("srof_gateway.keycloak_auth.jwt.PyJWKClient")
    async def test_valid_token(self, jwks_cls, decode):
        jwks_cls.return_value.get_signing_key_from_jwt.return_value.key = "PUBLIC"
        decode.return_value = {
            "iss": self.cfg.issuer,
            "aud": self.cfg.resource,
            "sub": "founder-123",
            "azp": "https://chatgpt.com/oauth/client.json",
            "scope": "openid offline_access srof:read",
            "exp": 2000000000,
        }
        verifier = KeycloakJWTVerifier(self.cfg)
        result = await verifier.verify_token("header.payload.signature")
        self.assertIsNotNone(result)
        assert result is not None
        self.assertEqual(result.resource, self.cfg.resource)
        self.assertEqual(result.subject, "founder-123")
        self.assertIn("srof:read", result.scopes)

    @patch("srof_gateway.keycloak_auth.jwt.decode")
    @patch("srof_gateway.keycloak_auth.jwt.PyJWKClient")
    async def test_missing_scope_fails_closed(self, jwks_cls, decode):
        jwks_cls.return_value.get_signing_key_from_jwt.return_value.key = "PUBLIC"
        decode.return_value = {
            "iss": self.cfg.issuer,
            "aud": self.cfg.resource,
            "sub": "founder-123",
            "scope": "openid",
            "exp": 2000000000,
        }
        verifier = KeycloakJWTVerifier(self.cfg)
        self.assertIsNone(await verifier.verify_token("token"))

    @patch("srof_gateway.keycloak_auth.jwt.PyJWKClient")
    async def test_invalid_signature_fails_closed(self, jwks_cls):
        jwks_cls.return_value.get_signing_key_from_jwt.side_effect = jwt.InvalidTokenError("bad")
        verifier = KeycloakJWTVerifier(self.cfg)
        self.assertIsNone(await verifier.verify_token("bad"))


if __name__ == "__main__":
    unittest.main(verbosity=2)
