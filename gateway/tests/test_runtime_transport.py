from __future__ import annotations

import srof_gateway.server as server


def test_runtime_settings_default_to_loopback(monkeypatch):
    monkeypatch.delenv("SROF_MCP_HOST", raising=False)
    monkeypatch.delenv("SROF_MCP_PORT", raising=False)
    monkeypatch.delenv("SROF_MCP_PATH", raising=False)

    assert server._mcp_runtime_settings() == {
        "host": "127.0.0.1",
        "port": 8765,
        "streamable_http_path": "/mcp",
    }


def test_run_gateway_uses_streamable_http_without_unsupported_kwargs(monkeypatch):
    calls = []
    monkeypatch.delenv("SROF_MCP_TRANSPORT", raising=False)
    monkeypatch.setattr(server.mcp, "run", lambda **kwargs: calls.append(kwargs))

    server.run_gateway()

    assert calls == [{"transport": "streamable-http"}]


def test_gateway_stdio_is_explicit(monkeypatch):
    calls = []
    monkeypatch.setenv("SROF_MCP_TRANSPORT", "stdio")
    monkeypatch.setattr(server.mcp, "run", lambda **kwargs: calls.append(kwargs))

    server.run_gateway()

    assert calls == [{}]


def test_gateway_rejects_unknown_transport(monkeypatch):
    monkeypatch.setenv("SROF_MCP_TRANSPORT", "bogus")

    try:
        server.run_gateway()
    except ValueError:
        pass
    else:
        raise AssertionError("unknown transport must fail")
