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
        connection.execute(
            """
            CREATE TABLE IF NOT EXISTS hidden_tasks (
                task_id TEXT PRIMARY KEY,
                task_title TEXT NOT NULL,
                class_name TEXT NOT NULL,
                hidden_at TEXT NOT NULL
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


def hide_task(
    vault_path: Path,
    task_id: str,
    task_title: str,
    class_name: str,
    hidden_at: str,
) -> None:
    _ensure_db(vault_path)
    with sqlite3.connect(vault_path) as connection:
        connection.execute(
            """
            INSERT INTO hidden_tasks (task_id, task_title, class_name, hidden_at)
            VALUES (?, ?, ?, ?)
            ON CONFLICT(task_id)
            DO UPDATE SET
                task_title = excluded.task_title,
                class_name = excluded.class_name,
                hidden_at = excluded.hidden_at
            """,
            (task_id, task_title, class_name, hidden_at),
        )
        connection.commit()


def recover_task(vault_path: Path, task_id: str) -> bool:
    _ensure_db(vault_path)
    with sqlite3.connect(vault_path) as connection:
        cursor = connection.execute(
            """
            DELETE FROM hidden_tasks
            WHERE task_id = ?
            """,
            (task_id,),
        )
        connection.commit()
    return cursor.rowcount > 0


def permanently_delete_task(vault_path: Path, task_id: str) -> bool:
    return recover_task(vault_path, task_id)


def list_hidden_tasks(vault_path: Path, limit: int = 500) -> list[dict[str, Any]]:
    _ensure_db(vault_path)
    with sqlite3.connect(vault_path) as connection:
        connection.row_factory = sqlite3.Row
        rows = connection.execute(
            """
            SELECT task_id, task_title, class_name, hidden_at
            FROM hidden_tasks
            ORDER BY datetime(hidden_at) DESC, task_id DESC
            LIMIT ?
            """,
            (limit,),
        ).fetchall()

    return [dict(row) for row in rows]


def list_hidden_task_ids(vault_path: Path) -> set[str]:
    _ensure_db(vault_path)
    with sqlite3.connect(vault_path) as connection:
        rows = connection.execute(
            """
            SELECT task_id
            FROM hidden_tasks
            """
        ).fetchall()

    return {row[0] for row in rows}