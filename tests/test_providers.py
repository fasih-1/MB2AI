"""Provider routing and the shared retry/backoff loop.

No network: the concrete backends are exercised through a fake subclass, so
these tests never need an API key.
"""

from __future__ import annotations

import logging
from pathlib import Path

import pytest

from src import providers as P

from tests.conftest import make_settings

LOG = logging.getLogger("test")


class FakeProvider(P.LLMProvider):
    """Records calls and fails a configurable number of times first."""

    def __init__(self, name="fake", failures=0, exc=None, **kwargs):
        super().__init__("key", f"{name}-model", LOG)
        self.name = name
        self.calls = 0
        self._failures = failures
        self._exc = exc or RuntimeError("429 Too Many Requests, retry in 0s")
        for key, value in kwargs.items():
            setattr(self, key, value)

    def _complete(self, request: P.GenerationRequest) -> str:
        self.calls += 1
        if self.calls <= self._failures:
            raise self._exc
        return f"ok from {self.name}"


def request(prompt="hello"):
    return P.GenerationRequest(system_instruction="sys", prompt=prompt)


class TestErrorClassification:
    @pytest.mark.parametrize(
        "message",
        [
            "429 Too Many Requests",
            "RESOURCE_EXHAUSTED",
            "Request timeout",
            "deadline exceeded",
            "503 Service Unavailable",
        ],
    )
    def test_retryable(self, message: str):
        assert P.is_retryable_error(RuntimeError(message)) is True

    @pytest.mark.parametrize(
        "message",
        ["401 Unauthorized", "API_KEY_INVALID", "permission_denied", "invalid api key"],
    )
    def test_auth_errors(self, message: str):
        assert P.is_auth_error(RuntimeError(message)) is True

    def test_ordinary_errors_are_neither(self):
        exc = ValueError("something else broke")
        assert not P.is_retryable_error(exc)
        assert not P.is_auth_error(exc)

    @pytest.mark.parametrize(
        "message,expected",
        [
            ("Please retry in 59 seconds", 59),
            ("retry in 12.5s", 13),
            ("retry_delay { seconds: 30 }", 30),
            ("no delay mentioned", None),
        ],
    )
    def test_extracts_server_supplied_delay(self, message, expected):
        assert P.extract_retry_delay_seconds(RuntimeError(message)) == expected


class TestRetryLoop:
    def test_recovers_after_transient_failures(self):
        provider = FakeProvider(failures=2, backoff_schedule=(0, 0, 0))
        assert provider.generate(request()) == "ok from fake"
        assert provider.calls == 3

    def test_gives_up_after_the_schedule(self):
        provider = FakeProvider(failures=99, backoff_schedule=(0, 0, 0))
        with pytest.raises(P.LLMError):
            provider.generate(request())
        assert provider.calls == 4

    def test_auth_errors_are_not_retried(self):
        provider = FakeProvider(
            failures=99, exc=RuntimeError("401 invalid api key"),
            backoff_schedule=(0, 0, 0),
        )
        with pytest.raises(P.LLMAuthError):
            provider.generate(request())
        assert provider.calls == 1

    def test_non_retryable_errors_fail_immediately(self):
        provider = FakeProvider(
            failures=99, exc=ValueError("malformed"), backoff_schedule=(0, 0, 0)
        )
        with pytest.raises(P.LLMError):
            provider.generate(request())
        assert provider.calls == 1


class TestRouting:
    def build(self, **providers):
        return P.ProviderRouter(providers, LOG, threshold_chars=12000)

    def test_small_prompts_go_to_groq(self):
        groq, gemini = FakeProvider("groq"), FakeProvider("gemini")
        router = self.build(groq=groq, gemini=gemini)
        assert router.select(500).name == "groq"

    def test_large_prompts_go_to_gemini(self):
        groq, gemini = FakeProvider("groq"), FakeProvider("gemini")
        router = self.build(groq=groq, gemini=gemini)
        assert router.select(50000).name == "gemini"

    def test_threshold_is_inclusive(self):
        groq, gemini = FakeProvider("groq"), FakeProvider("gemini")
        router = self.build(groq=groq, gemini=gemini)
        assert router.select(11999).name == "groq"
        assert router.select(12000).name == "gemini"

    def test_falls_back_when_gemini_is_unconfigured(self):
        """Gemini is optional; a large prompt must still be served."""
        router = self.build(groq=FakeProvider("groq"))
        assert router.select(50000).name == "groq"

    def test_single_provider_serves_everything(self):
        router = self.build(gemini=FakeProvider("gemini"))
        assert router.select(10).name == "gemini"
        assert router.select(999999).name == "gemini"

    def test_no_providers_is_an_error(self):
        with pytest.raises(P.NoProviderAvailableError):
            P.ProviderRouter({}, LOG)

    def test_forced_provider_overrides_size(self):
        groq, gemini = FakeProvider("groq"), FakeProvider("gemini")
        router = P.ProviderRouter(
            {"groq": groq, "gemini": gemini}, LOG, forced_provider="gemini"
        )
        assert router.select(10).name == "gemini"

    def test_forcing_an_unconfigured_provider_is_an_error(self):
        with pytest.raises(P.NoProviderAvailableError):
            P.ProviderRouter(
                {"groq": FakeProvider("groq")}, LOG, forced_provider="gemini"
            )


class TestBuildRouter:
    def test_skips_backends_without_a_key(self, tmp_path: Path):
        settings = make_settings(tmp_path, tmp_path / "v.db")
        router = P.build_router(settings, LOG)
        assert router.available == ["groq"]

    def test_includes_gemini_when_keyed(self, tmp_path: Path):
        settings = make_settings(tmp_path, tmp_path / "v.db", gemini_api_key="k")
        router = P.build_router(settings, LOG)
        assert router.available == ["gemini", "groq"]

    def test_honours_llm_provider_setting(self, tmp_path: Path):
        settings = make_settings(
            tmp_path, tmp_path / "v.db", gemini_api_key="k", llm_provider="gemini"
        )
        assert P.build_router(settings, LOG).forced_provider == "gemini"

    def test_auto_means_no_forced_provider(self, tmp_path: Path):
        settings = make_settings(tmp_path, tmp_path / "v.db", llm_provider="auto")
        assert P.build_router(settings, LOG).forced_provider is None

    def test_missing_every_key_raises(self, tmp_path: Path):
        settings = make_settings(
            tmp_path, tmp_path / "v.db", groq_api_key="", gemini_api_key=""
        )
        with pytest.raises(P.NoProviderAvailableError):
            P.build_router(settings, LOG)

    def test_respects_a_custom_threshold(self, tmp_path: Path):
        settings = make_settings(
            tmp_path, tmp_path / "v.db", gemini_api_key="k",
            llm_large_context_chars=100,
        )
        router = P.build_router(settings, LOG)
        assert router.select(150).name == "gemini"


class TestProviderBudgets:
    def test_groq_keeps_the_original_truncation_budget(self):
        assert P.GroqProvider.max_description_chars == 1500

    def test_gemini_allows_far_more_context(self):
        assert (
            P.GeminiProvider.max_description_chars
            > P.GroqProvider.max_description_chars
        )

    def test_pacing_matches_the_slower_free_tier(self):
        """Groq's 15s pace was hard-coded for every call; Gemini's higher RPM
        headroom means it should not pay that cost."""
        assert P.GeminiProvider.pacing_seconds < P.GroqProvider.pacing_seconds
