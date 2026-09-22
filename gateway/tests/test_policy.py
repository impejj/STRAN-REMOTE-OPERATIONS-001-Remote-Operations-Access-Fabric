from srof_gateway.policy import (
    HostPolicy,
    path_allowed,
    require_repository,
    require_service,
)


def policy() -> HostPolicy:
    return HostPolicy(
        host_id="SERVER",
        ssh_alias="server",
        capabilities=frozenset({"FILESYSTEM", "SYSTEMD", "GIT"}),
        allowed_roots=("/srv/scientiam", "/srv/scientiam/workspace"),
        allowed_services=frozenset({"scientiam-example.service"}),
        allowed_containers=frozenset(),
        allowed_repositories=frozenset({"/srv/scientiam/repos/scientiam"}),
        lifecycle_state="AUTHORIZED",
    )


def test_path_guard():
    p = policy()
    assert path_allowed("/srv/scientiam/runtime/a.json", p.allowed_roots)
    assert not path_allowed("/etc/shadow", p.allowed_roots)
    assert not path_allowed("../etc/passwd", p.allowed_roots)


def test_service_allowlist():
    p = policy()
    require_service(p, "scientiam-example.service")

    try:
        require_service(p, "ssh.service")
    except PermissionError:
        pass
    else:
        raise AssertionError("non-allowlisted service must fail")


def test_repository_allowlist():
    p = policy()
    require_repository(p, "/srv/scientiam/repos/scientiam")

    try:
        require_repository(p, "/tmp/random-repo")
    except PermissionError:
        pass
    else:
        raise AssertionError("non-allowlisted repository must fail")
