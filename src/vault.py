from __future__ import annotations

import sqlite3
from pathlib import Path
from typing import Any


def _ensure_db(vault_path: Path) -> None:
    vault_path.parent.mkdir(parents=True, exist_ok=True)
    with sqlite3.connect(vault_path) as connection:
        connection.execute(
            """
            CREATE TABLE IF NOT EXISTS drafts (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                task_title TEXT NOT NULL,
                class_name TEXT NOT NULL,
                mode TEXT NOT NULL,
                created_at TEXT NOT NULL,
                content TEXT NOT NULL
            )
            """
        )
        connection.commit()


def save_draft(
    vault_path: Path,
    task_title: str,
    class_name: str,
    mode: str,
    created_at: str,
    content: str,
) -> None:
    _ensure_db(vault_path)
    with sqlite3.connect(vault_path) as connection:
        connection.execute(
            """
            INSERT INTO drafts (task_title, class_name, mode, created_at, content)
            VALUES (?, ?, ?, ?, ?)
            """,
            (task_title, class_name, mode, created_at, content),
        )
        connection.commit()


def list_drafts(vault_path: Path, limit: int = 200) -> list[dict[str, Any]]:
    _ensure_db(vault_path)
    with sqlite3.connect(vault_path) as connection:
        connection.row_factory = sqlite3.Row
        rows = connection.execute(
            """
            SELECT id, task_title, class_name, mode, created_at, content
            FROM drafts
            ORDER BY datetime(created_at) DESC, id DESC
            LIMIT ?
            """,
            (limit,),
        ).fetchall()

    return [dict(row) for row in rows]