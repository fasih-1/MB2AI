"""OS trust store injection.

Antivirus and proxy software that scans HTTPS presents its own certificate,
signed by a root installed in the OS store but absent from certifi's bundle.
Python then fails every LLM call with CERTIFICATE_VERIFY_FAILED, which looks
like a bad API key and is not.
"""

from __future__ import annotations

import logging
import sys

import pytest

from src import tls


@pytest.fixture(autouse=True)
def _reset_installed_flag():
    original = tls._installed
    tls._installed = False
    yield
    tls._installed = original


def test_enables_the_system_trust_store():
    assert tls.enable_system_trust_store() is True


def test_is_idempotent():
    assert tls.enable_system_trust_store() is True
    # The second call short-circuits rather than injecting twice.
    assert tls.enable_system_trust_store() is True


def test_logs_when_enabled(caplog):
    with caplog.at_level(logging.INFO):
        tls.enable_system_trust_store(logging.getLogger("test"))
    assert "TLS_SYSTEM_TRUST_STORE_ENABLED" in caplog.text


def test_falls_back_quietly_without_truststore(monkeypatch, caplog):
    """certifi verification is correct on machines with no interception, so a
    missing dependency must not be fatal."""
    monkeypatch.setitem(sys.modules, "truststore", None)
    monkeypatch.setattr(
        tls, "_installed", False, raising=False
    )

    real_import = __builtins__["__import__"] if isinstance(__builtins__, dict) \
        else __builtins__.__import__

    def fake_import(name, *args, **kwargs):
        if name == "truststore":
            raise ImportError("no truststore")
        return real_import(name, *args, **kwargs)

    monkeypatch.setattr("builtins.__import__", fake_import)
    with caplog.at_level(logging.INFO):
        assert tls.enable_system_trust_store(logging.getLogger("test")) is False
    assert "TLS_TRUSTSTORE_UNAVAILABLE" in caplog.text
