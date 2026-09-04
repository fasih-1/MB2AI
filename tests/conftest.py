"""Shared fixtures.

Every test runs against a temporary database. Nothing here touches the real
vault.db, the real .env, or the network.
"""

from __future__ import annotations

import json
import sqlite3
import sys
from pathlib import Path
from typing import Any

import pytest

PROJECT_ROOT = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(PROJECT_ROOT))

from src import vault  # noqa: E402
from src.config import Settings  # noqa: E402


@pytest.fixture(autouse=True)
def _clear_migration_cache():
    """vault caches which paths it has migrated, keyed by path string.

    Temp paths differ per test, but clearing keeps tests independent of
    execution order.
    """
    vault._migrated_paths.clear()
    yield
    vault._migrated_paths.clear()


@pytest.fixture
def vault_path(tmp_path: Path) -> Path:
    return tmp_path / "vault.db"


@pytest.fixture
def legacy_vault(tmp_path: Path) -> Path:
    """A pre-migration database: the original two tables, with rows.

    Mirrors the schema that shipped before the rework, including the
    index-based task ids that made hides fragile.
    """
    path = tmp_path / "legacy.db"
    connection = sqlite3.connect(path)
    connection.executescript(
        """
        CREATE TABLE drafts (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            task_title TEXT NOT NULL,
            class_name TEXT NOT NULL,
            mode TEXT NOT NULL,
            created_at TEXT NOT NULL,
            content TEXT NOT NULL
        );
        CREATE TABLE hidden_tasks (
            task_id TEXT PRIMARY KEY,
            task_title TEXT NOT NULL,
            class_name TEXT NOT NULL,
            hidden_at TEXT NOT NULL
        );
        """
    )
    connection.executemany(
        "INSERT INTO drafts (task_title, class_name, mode, created_at, content)"
        " VALUES (?, ?, ?, ?, ?)",
        [
            ("Homework 1 unit-4", "IB MYP I&S (Grade 10)", "tutor",
             "2026-04-29T05:00:00+00:00", "# draft one"),
            ("Summative Task 1", "IB MYP Biology (Grade 10)", "ghostwriter",
             "2026-04-28T05:00:00+00:00", "# draft two"),
        ],
    )
    connection.executemany(
        "INSERT INTO hidden_tasks (task_id, task_title, class_name, hidden_at)"
        " VALUES (?, ?, ?, ?)",
        [
            ("2-ib-myp-biology-grade-10-summative-task-1", "Summative Task 1",
             "IB MYP Biology (Grade 10)", "2026-04-20T05:00:00+00:00"),
            ("1-ib-myp-design-grade-10-class-task", "class task",
             "IB MYP Design (Grade 10)", "2026-04-21T05:00:00+00:00"),
        ],
    )
    connection.commit()
    connection.close()
    return path


def make_task(
    title: str,
    class_name: str,
    href: str | None = None,
    description: str = "Formative, Homework /10%, Pending",
    full_description: str = "Do the thing.",
    attachments: list[str] | None = None,
) -> dict[str, Any]:
    return {
        "title": title,
        "class_name": class_name,
        "description": description,
        "assignment_href": href,
        "full_description": full_description,
        "local_attachments": attachments or [],
        "due_date": "Apr 29, 11:40 AM",
        "parsed_cleanly": True,
        "parse_error": None,
    }


@pytest.fixture
def payload() -> dict[str, Any]:
    """A ScrapeOutput-shaped payload with a mix of href and href-less tasks."""
    return {
        "metadata": {
            "scraped_at": "2026-04-29T05:53:25.044198+00:00",
            "base_url": "https://example.managebac.com/student",
            "total_tasks": 3,
            "parse_errors_count": 0,
            "used_auth_state": True,
        },
        "tasks": [
            make_task(
                "Homework 1 unit-4",
                "IB MYP I&S (Grade 10)",
                href="/student/classes/12846944/core_tasks/47949059",
            ),
            make_task(
                "Formative 1",
                "IB MYP Mathematics (Grade 10)",
                href="/student/classes/12846973/core_tasks/47980820",
                description="Formative, Project /5%, Pending",
            ),
            # No href: exercises the content-hash identity fallback.
            make_task("Orphan Task", "IB MYP Design (Grade 10)"),
        ],
    }


@pytest.fixture
def seeded_vault(vault_path: Path, payload: dict[str, Any]) -> Path:
    vault.ingest_scrape_payload(vault_path, payload)
    return vault_path


def make_settings(tmp_path: Path, vault_db: Path, **overrides: Any) -> Settings:
    """Build Settings directly, so tests never read the developer's .env."""
    defaults: dict[str, Any] = {
        "username": "student",
        "password": "secret",
        "base_url": "https://example.managebac.com/student",
        "headless": True,
        "debug_mode": False,
        "navigation_timeout_ms": 30000,
        "action_timeout_ms": 15000,
        "retry_attempts": 3,
        "retry_backoff_seconds": 2,
        "groq_api_key": "test-groq-key",
        "groq_model": "llama-3.3-70b-versatile",
        "gemini_api_key": "",
        "gemini_model": "gemini-2.0-flash",
        "llm_provider": "auto",
        "llm_large_context_chars": 12000,
        "tasks_output_path": tmp_path / "tasks_raw.json",
        "auth_state_path": tmp_path / "auth_state.json",
        "vault_db_path": vault_db,
        "project_root": tmp_path,
    }
    defaults.update(overrides)
    return Settings(**defaults)


@pytest.fixture
def api_client(tmp_path: Path, seeded_vault: Path):
    """TestClient wired to a temp vault, with the JSON backfill disabled.

    The backfill only runs when the tasks table is empty, but the fixture
    vault is already seeded; pointing at a non-existent file makes that
    explicit rather than incidental.
    """
    from fastapi.testclient import TestClient

    from src import api

    settings = make_settings(tmp_path, seeded_vault)
    api._get_settings.cache_clear()
    original = api._get_settings
    api._get_settings = lambda: settings
    try:
        with TestClient(api.app) as client:
            yield client
    finally:
        api._get_settings = original
        api._get_settings.cache_clear()


@pytest.fixture
def write_tasks_json(tmp_path: Path):
    def _write(payload: dict[str, Any]) -> Path:
        path = tmp_path / "tasks_raw.json"
        path.write_text(json.dumps(payload), encoding="utf-8")
        return path

    return _write
