"""Make Python trust the same certificates the operating system does.

Python's HTTP clients verify against certifi's bundled CA list, which does not
include roots installed locally on the machine. Antivirus and corporate proxies
that scan HTTPS work by presenting their own certificate signed by such a root:
on this project's dev machine, Avast's "Web/Mail Shield Root". The browser and
curl accept it because they use the Windows certificate store; the Groq and
Gemini SDKs did not, and every generation failed with

    [SSL: CERTIFICATE_VERIFY_FAILED] unable to get local issuer certificate

which reads like a broken API key but is nothing of the sort.

truststore redirects verification to the OS trust store, so whatever the user's
machine already trusts, the app trusts too. Call enable_system_trust_store()
once at startup, before any HTTPS request.
"""

from __future__ import annotations

import logging

_installed = False


def enable_system_trust_store(logger: logging.Logger | None = None) -> bool:
    """Route TLS verification through the OS trust store.

    Returns True if it took effect. Safe to call more than once, and a no-op if
    truststore is not installed - verification then falls back to certifi,
    which is correct on machines without an intercepting proxy.
    """
    global _installed
    if _installed:
        return True

    try:
        import truststore

        truststore.inject_into_ssl()
        _installed = True
        if logger:
            logger.info("TLS_SYSTEM_TRUST_STORE_ENABLED")
        return True
    except ImportError:
        if logger:
            logger.info("TLS_TRUSTSTORE_UNAVAILABLE falling back to certifi")
        return False
    except Exception as exc:  # pragma: no cover - defensive
        if logger:
            logger.warning("TLS_TRUSTSTORE_FAILED reason=%s", exc)
        return False
