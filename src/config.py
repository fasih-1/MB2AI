from __future__ import annotations

from dataclasses import dataclass
from pathlib import Path
import os
import sys

from dotenv import load_dotenv


@dataclass(frozen=True)
class Settings:
    username: str
    password: str
    base_url: str
    headless: bool
    debug_mode: bool
    navigation_timeout_ms: int
    action_timeout_ms: int
    retry_attempts: int
    retry_backoff_seconds: int
    groq_api_key: str
    groq_model: str
    gemini_api_key: str
    gemini_model: str
    llm_provider: str
    llm_large_context_chars: int
    tasks_output_path: Path
    auth_state_path: Path
    vault_db_path: Path
    project_root: Path


def _to_bool(value: str | None, default: bool) -> bool:
    if value is None:
        return default
    return value.strip().lower() in {"1", "true", "yes", "on"}


def load_settings(force_headed: bool = False, debug_mode: bool = False) -> Settings:
    if getattr(sys, "frozen", False):
        # A PyInstaller-frozen __file__ resolves inside the onefile temp
        # extraction dir, not next to the shipped exe, so .env and vault.db
        # would silently land in a folder that's wiped after the process exits.
        project_root = Path(sys.executable).resolve().parent
    else:
        project_root = Path(__file__).resolve().parent.parent
    dotenv_path = project_root / ".env"
    load_dotenv(dotenv_path=dotenv_path, override=True)

    username = os.getenv("MANAGEBAC_USERNAME", "").strip()
    password = os.getenv("MANAGEBAC_PASSWORD", "").strip()
    base_url = os.getenv("MANAGEBAC_BASE_URL", "").strip()

    if not username or not password or not base_url:
        raise ValueError(
            "Missing required environment values. Set MANAGEBAC_USERNAME, "
            "MANAGEBAC_PASSWORD, and MANAGEBAC_BASE_URL in .env."
        )

    tasks_output_rel = os.getenv("TASKS_OUTPUT_PATH", "data/tasks_raw.json")
    auth_state_rel = os.getenv("AUTH_STATE_PATH", "data/auth_state.json")
    vault_db_rel = os.getenv("VAULT_DB_PATH", "vault.db")
    groq_api_key = os.getenv("GROQ_API_KEY", "").strip()
    groq_model = os.getenv("GROQ_MODEL", "openai/gpt-oss-20b").strip() or "openai/gpt-oss-20b"
    gemini_api_key = os.getenv("GEMINI_API_KEY", "").strip()
    gemini_model = os.getenv("GEMINI_MODEL", "gemini-3.6-flash").strip() or "gemini-3.6-flash"

    # "auto" routes by prompt size; "groq" or "gemini" pins one backend.
    llm_provider = os.getenv("LLM_PROVIDER", "auto").strip().lower() or "auto"

    return Settings(
        username=username,
        password=password,
        base_url=base_url.rstrip("/"),
        headless=False if force_headed else _to_bool(os.getenv("HEADLESS"), True),
        debug_mode=debug_mode,
        navigation_timeout_ms=int(os.getenv("NAVIGATION_TIMEOUT_MS", "30000")),
        action_timeout_ms=int(os.getenv("ACTION_TIMEOUT_MS", "15000")),
        retry_attempts=int(os.getenv("RETRY_ATTEMPTS", "3")),
        retry_backoff_seconds=int(os.getenv("RETRY_BACKOFF_SECONDS", "2")),
        groq_api_key=groq_api_key,
        groq_model=groq_model,
        gemini_api_key=gemini_api_key,
        gemini_model=gemini_model,
        llm_provider=llm_provider,
        llm_large_context_chars=int(os.getenv("LLM_LARGE_CONTEXT_CHARS", "12000")),
        tasks_output_path=(project_root / tasks_output_rel).resolve(),
        auth_state_path=(project_root / auth_state_rel).resolve(),
        vault_db_path=(project_root / vault_db_rel).resolve(),
        project_root=project_root,
    )
