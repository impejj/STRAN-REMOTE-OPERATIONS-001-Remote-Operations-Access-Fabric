from __future__ import annotations

from dataclasses import dataclass
from pathlib import PurePosixPath
from typing import Iterable


@dataclass(frozen=True)
class HostPolicy:
    host_id: str
    ssh_alias: str
    capabilities: frozenset[str]
    allowed_roots: tuple[str, ...]
    allowed_services: frozenset[str]
    allowed_containers: frozenset[str]
    allowed_repositories: frozenset[str]
    lifecycle_state: str

    @property
    def executable(self) -> bool:
        return self.lifecycle_state in {
            "AUTHORIZED", "HEALTH_OK", "EXECUTION_OK", "EVIDENCE_OK", "PRODUCTION_READY"
        }


def path_allowed(path: str, allowed_roots: Iterable[str]) -> bool:
    candidate = PurePosixPath(path)
    if not candidate.is_absolute():
        return False
    normalized = str(candidate)
    for root in allowed_roots:
        root_path = str(PurePosixPath(root))
        if normalized == root_path or normalized.startswith(root_path.rstrip("/") + "/"):
            return True
    return False


def require_capability(policy: HostPolicy, capability: str) -> None:
    if not policy.executable:
        raise PermissionError(f"host {policy.host_id} is not authorized for execution")
    if capability not in policy.capabilities:
        raise PermissionError(f"host {policy.host_id} lacks capability {capability}")


def require_path(policy: HostPolicy, path: str) -> None:
    require_capability(policy, "FILESYSTEM")
    if not path_allowed(path, policy.allowed_roots):
        raise PermissionError(f"path {path!r} is outside allowed roots on {policy.host_id}")


def require_service(policy: HostPolicy, service: str) -> None:
    require_capability(policy, "SYSTEMD")
    if service not in policy.allowed_services:
        raise PermissionError(f"service {service!r} is not allowlisted on {policy.host_id}")


def require_container(policy: HostPolicy, container: str) -> None:
    require_capability(policy, "DOCKER")
    if container not in policy.allowed_containers:
        raise PermissionError(f"container {container!r} is not allowlisted on {policy.host_id}")


def require_repository(policy: HostPolicy, repository: str) -> None:
    require_capability(policy, "GIT")
    if repository not in policy.allowed_repositories:
        raise PermissionError(f"repository {repository!r} is not allowlisted on {policy.host_id}")
