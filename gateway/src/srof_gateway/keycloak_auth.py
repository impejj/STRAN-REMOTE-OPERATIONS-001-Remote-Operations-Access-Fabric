from __future__ import annotations

import logging
import os
from dataclasses import dataclass

import jwt
from mcp.server.auth.provider import AccessToken, TokenVerifier

logger = logging.getLogger(__name__)


def _truthy(value: str | None) -> bool:
    return (value or "").strip().lower() in {"1", "true", "yes", "on"}


def _scopes(value: object) -> list[str]:
    if isinstance(value, str):
        return [x for x in value.split() if x]
    if isinstance(value, list):
        return [str(x) for x in value if str(x)]
    return []


@dataclass(frozen=True)
class OAuthRuntimeConfig:
    required: bool
    issuer: str
    resource: str
    required_scopes: tuple[str, ...]
    jwks_url: str
    algorithms: tuple[str, ...] = ("RS256",)

    @classmethod
    def from_env(cls) -> "OAuthRuntimeConfig":
        required = _truthy(os.environ.get("SROF_OAUTH_REQUIRED"))
        issuer = os.environ.get("SROF_OAUTH_ISSUER", "").strip().rstrip("/")
        resource = os.environ.get("SROF_OAUTH_RESOURCE", "").strip()
        scopes = tuple(
            x for x in os.environ.get("SROF_OAUTH_REQUIRED_SCOPES", "srof:read").split() if x
        )
        jwks_url = os.environ.get("SROF_OAUTH_JWKS_URL", "").strip()
        algorithms = tuple(
            x for x in os.environ.get("SROF_OAUTH_ALGORITHMS", "RS256").replace(",", " ").split() if x
        )

        if required:
            missing = [
                name
                for name, value in (
                    ("SROF_OAUTH_ISSUER", issuer),
                    ("SROF_OAUTH_RESOURCE", resource),
                    ("SROF_OAUTH_REQUIRED_SCOPES", scopes),
                )
                if not value
            ]
            if missing:
                raise RuntimeError("OAuth required but missing: " + ", ".join(missing))
            if not issuer.startswith("https://"):
                raise RuntimeError("SROF_OAUTH_ISSUER must be https:// in required mode")
            if not resource.startswith("https://"):
                raise RuntimeError("SROF_OAUTH_RESOURCE must be https:// in required mode")

        if not jwks_url and issuer:
            jwks_url = issuer + "/protocol/openid-connect/certs"

        return cls(
            required=required,
            issuer=issuer,
            resource=resource,
            required_scopes=scopes,
            jwks_url=jwks_url,
            algorithms=algorithms or ("RS256",),
        )


class KeycloakJWTVerifier(TokenVerifier):
    """Verify Keycloak JWT access tokens for the SROF MCP resource."""

    def __init__(self, config: OAuthRuntimeConfig) -> None:
        if not config.required:
            raise ValueError("KeycloakJWTVerifier requires OAuthRuntimeConfig.required=true")
        self.config = config
        self._jwks = jwt.PyJWKClient(config.jwks_url, cache_keys=True)

    async def verify_token(self, token: str) -> AccessToken | None:
        try:
            signing_key = self._jwks.get_signing_key_from_jwt(token).key
            claims = jwt.decode(
                token,
                signing_key,
                algorithms=list(self.config.algorithms),
                issuer=self.config.issuer,
                audience=self.config.resource,
                leeway=30,
                options={"require": ["exp", "iss", "aud", "sub"]},
            )
            scopes = _scopes(claims.get("scope"))
            if not set(self.config.required_scopes).issubset(scopes):
                logger.warning("Rejected OAuth token with insufficient SROF scope")
                return None

            client_id = str(
                claims.get("azp")
                or claims.get("client_id")
                or claims.get("clientId")
                or "unknown"
            )
            exp = claims.get("exp")
            return AccessToken(
                token=token,
                client_id=client_id,
                scopes=scopes,
                expires_at=int(exp) if exp is not None else None,
                resource=self.config.resource,
                subject=str(claims["sub"]),
                claims=dict(claims),
            )
        except Exception as exc:
            logger.warning("Rejected OAuth token: %s", type(exc).__name__)
            return None
