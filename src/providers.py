from __future__ import annotations

import logging
import math
import re
import time
from abc import ABC, abstractmethod
from dataclasses import dataclass
from typing import Any, Optional


class LLMError(RuntimeError):
    """Any failure raised by a provider after its retries are exhausted."""


class LLMAuthError(LLMError):
    """Bad or missing credentials. Never retried."""


class NoProviderAvailableError(LLMError):
    """No provider has an API key configured."""


@dataclass(frozen=True)
class GenerationRequest:
    system_instruction: str
    prompt: str
    max_tokens: int = 900


# ---------------------------------------------------------------------------
# Error classification
#
# Carried over from brain.py unchanged: this backoff behaviour is tuned for
# free-tier rate limits and both backends surface rate limits as text.
# ---------------------------------------------------------------------------


def is_retryable_error(exc: Exception) -> bool:
    message = str(exc).lower()
    return (
        "429" in message
        or "too many requests" in message
        or "resource_exhausted" in message
        or "timeout" in message
        or "timed out" in message
        or "deadline exceeded" in message
        or "503" in message
        or "unavailable" in message
    )


def is_auth_error(exc: Exception) -> bool:
    message = str(exc).lower()
    return (
        "api_key_invalid" in message
        or "401" in message
        or "permission_denied" in message
        or "invalid api key" in message
        or "unauthenticated" in message
    )


def extract_retry_delay_seconds(exc: Exception) -> Optional[int]:
    message = str(exc).lower()

    # Examples we handle:
    # - "retry in 59 seconds"
    # - "retry in 12.5s"
    # - "retry_delay { seconds: 59 }"
    patterns = [
        r"retry\s+in\s+([0-9]+(?:\.[0-9]+)?)\s*(?:seconds|second|secs|sec|s)",
        r"retry_delay[^\d]*([0-9]+(?:\.[0-9]+)?)",
    ]

    for pattern in patterns:
        match = re.search(pattern, message)
        if not match:
            continue
        try:
            return max(1, int(math.ceil(float(match.group(1)))))
        except Exception:
            continue

    return None


# ---------------------------------------------------------------------------
# Providers
# ---------------------------------------------------------------------------


class LLMProvider(ABC):
    """One free LLM backend.

    Subclasses implement `_complete`; the retry/backoff loop, which is the part
    tuned for free-tier limits, lives here so every backend inherits it.
    """

    name: str = "unknown"

    #: Description budget before brain.py truncates. Sized to the model's
    #: context window, not to a fixed constant.
    max_description_chars: int = 1500

    #: Cooldown between generations, sized to the free tier's requests/minute.
    pacing_seconds: int = 15

    backoff_schedule: tuple[int, ...] = (15, 30, 60)

    def __init__(self, api_key: str, model: str, logger: logging.Logger) -> None:
        self.api_key = api_key
        self.model = model
        self.logger = logger

    @abstractmethod
    def _complete(self, request: GenerationRequest) -> str:
        """Single call to the backend. Raises on failure."""

    def generate(self, request: GenerationRequest) -> str:
        max_attempts = 1 + len(self.backoff_schedule)

        for attempt in range(1, max_attempts + 1):
            try:
                return self._complete(request)
            except Exception as exc:
                if is_auth_error(exc):
                    raise LLMAuthError(f"{self.name}: {exc}") from exc

                if is_retryable_error(exc) and attempt < max_attempts:
                    parsed_delay = extract_retry_delay_seconds(exc)
                    delay = (
                        parsed_delay
                        if parsed_delay is not None
                        else self.backoff_schedule[attempt - 1]
                    )
                    self.logger.warning(
                        "GEN_RETRY provider=%s attempt=%s/%s delay_s=%s reason=%s",
                        self.name,
                        attempt,
                        max_attempts,
                        delay,
                        exc,
                    )
                    time.sleep(delay)
                    continue

                raise LLMError(f"{self.name}: {exc}") from exc

        raise LLMError(f"{self.name}: retries exhausted")


class GroqProvider(LLMProvider):
    """Groq free tier: ~30 requests/minute, Llama 3.3 70B, 8k context.

    The fast default for tutor-mode outlining.
    """

    name = "groq"
    max_description_chars = 1500
    pacing_seconds = 15

    def __init__(self, api_key: str, model: str, logger: logging.Logger) -> None:
        super().__init__(api_key, model, logger)
        self._client: Any = None

    def _get_client(self) -> Any:
        if self._client is None:
            from groq import Groq

            self._client = Groq(api_key=self.api_key)
        return self._client

    def _complete(self, request: GenerationRequest) -> str:
        response = self._get_client().chat.completions.create(
            model=self.model,
            messages=[
                {"role": "system", "content": request.system_instruction},
                {"role": "user", "content": request.prompt},
            ],
            # Keep output bounded to reduce TPM pressure on free tier.
            max_tokens=request.max_tokens,
        )

        choices = getattr(response, "choices", None) or []
        if not choices:
            raise ValueError("Groq returned no choices.")

        content = getattr(getattr(choices[0], "message", None), "content", None)
        if isinstance(content, str) and content.strip():
            return content.strip()

        raise ValueError("Groq returned an empty response.")


class GeminiProvider(LLMProvider):
    """Gemini free tier: ~15 requests/minute, ~500/day, very large context.

    Used when a prompt carries more context than Groq's window takes.
    """

    name = "gemini"
    max_description_chars = 60000
    pacing_seconds = 4

    def __init__(self, api_key: str, model: str, logger: logging.Logger) -> None:
        super().__init__(api_key, model, logger)
        self._client: Any = None

    def _get_client(self) -> Any:
        if self._client is None:
            from google import genai

            self._client = genai.Client(api_key=self.api_key)
        return self._client

    def _complete(self, request: GenerationRequest) -> str:
        from google.genai import types

        response = self._get_client().models.generate_content(
            model=self.model,
            contents=request.prompt,
            config=types.GenerateContentConfig(
                system_instruction=request.system_instruction,
                max_output_tokens=request.max_tokens,
            ),
        )

        text = getattr(response, "text", None)
        if isinstance(text, str) and text.strip():
            return text.strip()

        raise ValueError("Gemini returned an empty response.")


# ---------------------------------------------------------------------------
# Routing
# ---------------------------------------------------------------------------

DEFAULT_LARGE_CONTEXT_CHARS = 12000


class ProviderRouter:
    """Picks a backend by estimated prompt size.

    Small prompts go to Groq because it is faster; prompts past the threshold
    go to Gemini because they will not fit Groq's window. With only one
    provider configured, everything routes to it.
    """

    def __init__(
        self,
        providers: dict[str, LLMProvider],
        logger: logging.Logger,
        default_provider: str = "groq",
        large_context_provider: str = "gemini",
        threshold_chars: int = DEFAULT_LARGE_CONTEXT_CHARS,
        forced_provider: str | None = None,
    ) -> None:
        if not providers:
            raise NoProviderAvailableError(
                "No LLM provider is configured. Set GROQ_API_KEY or GEMINI_API_KEY in .env."
            )

        self.providers = providers
        self.logger = logger
        self.default_provider = default_provider
        self.large_context_provider = large_context_provider
        self.threshold_chars = threshold_chars
        self.forced_provider = forced_provider

        if forced_provider and forced_provider not in providers:
            raise NoProviderAvailableError(
                f"LLM_PROVIDER is '{forced_provider}' but no API key is configured for it."
            )

    @property
    def available(self) -> list[str]:
        return sorted(self.providers)

    def _fallback(self) -> LLMProvider:
        for name in (self.default_provider, self.large_context_provider):
            if name in self.providers:
                return self.providers[name]
        return next(iter(self.providers.values()))

    def select(self, prompt_chars: int) -> LLMProvider:
        if self.forced_provider:
            return self.providers[self.forced_provider]

        if prompt_chars >= self.threshold_chars:
            large = self.providers.get(self.large_context_provider)
            if large is not None:
                return large
            self.logger.info(
                "LLM_ROUTE_FALLBACK reason=large_context_provider_unavailable chars=%s",
                prompt_chars,
            )

        return self._fallback()

    def describe(self) -> str:
        if self.forced_provider:
            return f"forced={self.forced_provider}"
        return (
            f"available={','.join(self.available)} "
            f"default={self.default_provider} "
            f"large_context={self.large_context_provider} "
            f"threshold_chars={self.threshold_chars}"
        )


def build_router(settings: Any, logger: logging.Logger) -> ProviderRouter:
    """Construct a router from settings, skipping backends with no API key."""
    providers: dict[str, LLMProvider] = {}

    if getattr(settings, "groq_api_key", ""):
        providers["groq"] = GroqProvider(
            api_key=settings.groq_api_key,
            model=settings.groq_model,
            logger=logger,
        )

    if getattr(settings, "gemini_api_key", ""):
        providers["gemini"] = GeminiProvider(
            api_key=settings.gemini_api_key,
            model=settings.gemini_model,
            logger=logger,
        )

    forced = (getattr(settings, "llm_provider", "auto") or "auto").strip().lower()
    forced_provider = None if forced in {"", "auto"} else forced

    return ProviderRouter(
        providers=providers,
        logger=logger,
        threshold_chars=getattr(
            settings, "llm_large_context_chars", DEFAULT_LARGE_CONTEXT_CHARS
        ),
        forced_provider=forced_provider,
    )
