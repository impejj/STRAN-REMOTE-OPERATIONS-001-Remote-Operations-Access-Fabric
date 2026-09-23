from __future__ import annotations

import os
from unittest.mock import patch

import pytest

import srof_gateway.server as server


def test_gateway_defaults_to_loopback_streamable_http(monkeypatch):
    calls = []
    monkeypatch.delenv("SROF_MCP_TRANSPORT", raising=False)
    monkeypatch.delenv("SROF_MCP_HOST", raising=False)
    monkeypatch.delenv("SROF_MCP_PORT", raising=False)
    monkeypatch.delenv("SROF_MCP_PATH", raising=False)

    monkeypatch.setattr(server.mcp, "run", lambda **kwargs: calls.append(kwargs))
    server.run_gateway()

    assert calls == [{
        "transport": "streamable-http",
        "host": "127.0.0.1",
        "port": 8765,
        "streamable_http_path": "/mcp",
    }]


def test_gateway_stdio_is_explicit(monkeypatch):
    calls = []
    monkeypatch.setenv("SROF_MCP_TRANSPORT", "stdio")
    monkeypatch.setattr(server.mcp, "run", lambda **kwargs: calls.append(kwargs))
    server.run_gateway()
    assert calls == [{}]


def test_gateway_rejects_unknown_transport(monkeypatch):
    monkeypatch.setenv("SROF_MCP_TRANSPORT", "bogus")
    with pytest.raises(ValueError):
        server.run_gateway()
