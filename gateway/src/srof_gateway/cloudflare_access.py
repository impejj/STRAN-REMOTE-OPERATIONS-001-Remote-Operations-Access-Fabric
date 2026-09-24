from __future__ import annotations

import os
from dataclasses import dataclass
from typing import Any

import jwt


@dataclass(frozen=True)
class CloudflareAccessConfig:
    team_domain: str
    audience: str
    required: bool = False

    @property
    def issuer(self) -> str:
        return f"https://{self.team_domain}"

    @property
    def certs_url(self) -> str:
        return f"{self.issuer}/cdn-cgi/access/certs"

    @classmethod
    def from_env(cls) -> "CloudflareAccessConfig":
        required = os.environ.get("SROF_CF_ACCESS_REQUIRED", "0").strip().lower() in {
            "1", "true", "yes", "on"
        }
        team_domain = os.environ.get("SROF_CF_TEAM_DOMAIN", "").strip().rstrip("/")
        audience = os.environ.get("SROF_CF_ACCESS_AUD", "").strip()
        if required and (not team_domain or not audience):
            raise RuntimeError(
                "Cloudflare Access enforcement requires SROF_CF_TEAM_DOMAIN "
                "and SROF_CF_ACCESS_AUD"
            )
        return cls(team_domain=team_domain, audience=audience, required=required)


class CloudflareAccessVerifier:
    def __init__(self, config: CloudflareAccessConfig):
        self.config = config
        self._jwks = jwt.PyJWKClient(config.certs_url) if config.required else None

    def verify(self, token: str) -> dict[str, Any]:
        if not self.config.required:
            return {}
        if not token:
            raise jwt.InvalidTokenError("missing Cf-Access-Jwt-Assertion")
        assert self._jwks is not None
        signing_key = self._jwks.get_signing_key_from_jwt(token).key
        claims = jwt.decode(
            token,
            signing_key,
            algorithms=["RS256"],
            audience=self.config.audience,
            issuer=self.config.issuer,
        )
        return dict(claims)


def _header(scope: dict[str, Any], name: str) -> str:
    wanted = name.lower().encode("ascii")
    for key, value in scope.get("headers", []):
        if key.lower() == wanted:
            return value.decode("latin-1")
    return ""


class CloudflareAccessMiddleware:
    """Fail-closed ASGI guard for Cloudflare Access protected HTTP traffic."""

    def __init__(self, app: Any, verifier: CloudflareAccessVerifier):
        self.app = app
        self.verifier = verifier

    async def __call__(self, scope: dict[str, Any], receive: Any, send: Any) -> None:
        if scope.get("type") != "http" or not self.verifier.config.required:
            await self.app(scope, receive, send)
            return

        token = _header(scope, "cf-access-jwt-assertion")
        try:
            claims = self.verifier.verify(token)
        except Exception:
            await send(
                {
                    "type": "http.response.start",
                    "status": 403,
                    "headers": [(b"content-type", b"application/json")],
                }
            )
            await send(
                {
                    "type": "http.response.body",
                    "body": b'{"error":"CLOUDFLARE_ACCESS_JWT_INVALID"}',
                }
            )
            return

        scope.setdefault("state", {})["cloudflare_access_claims"] = claims
        await self.app(scope, receive, send)
