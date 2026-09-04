from __future__ import annotations

import hashlib
import json
import re
import shutil
import sqlite3
from contextlib import contextmanager
from datetime import datetime, timezone
from pathlib import Path
from typing import Any, Iterable, Iterator, Optional

from .rubric import extract_criteria, merge_criteria


SCHEMA_VERSION = 1

DEFAULT_SOURCE = "managebac"
KNOWN_SOURCES = ("managebac", "kognity")

ITEM_TYPE_TASK = "task"
ITEM_TYPE_CONTENT_BLOCK = "content_block"

_TASK_ID_PATTERNS = (
    re.compile(r"core_tasks/(\d+)"),
    re.compile(r"tasks/(\d+)"),
    re.compile(r"assignments/(\d+)"),
)

_CLASS_ID_PATTERN = re.compile(r"classes/(\d+)")

_TASK_TYPES = {"formative", "summative"}
_TASK_STATUSES = {
    "pending",
    "submitted",
    "overdue",
    "graded",
    "complete",
    "completed",
    "draft",
    "late",
    "missing",
    "upcoming",
}


def _now() -> str:
    return datetime.now(timezone.utc).isoformat()


def _normalize(value: str | None) -> str:
    return re.sub(r"\s+", " ", (value or "").strip()).casefold()


# ---------------------------------------------------------------------------
# Stable identity helpers
# ---------------------------------------------------------------------------


def derive_source_task_id(
    assignment_href: str | None,
    class_name: str | None,
    title: str | None,
) -> str:
    """Stable, index-free task identity.

    Prefers the numeric id embedded in the ManageBac assignment URL. Falls back
    to a content hash of class + title so re-ordering the dashboard never
    changes an id (the old index-based scheme did exactly that).
    """
    href = (assignment_href or "").strip()
    for pattern in _TASK_ID_PATTERNS:
        match = pattern.search(href)
        if match:
            return match.group(1)

    return alias_key_for(class_name, title)


def alias_key_for(subject_name: str | None, title: str | None) -> str:
    """Content-derived alias so hides survive an id scheme change."""
    digest = hashlib.sha1(
        f"{_normalize(subject_name)}::{_normalize(title)}".encode("utf-8")
    ).hexdigest()
    return f"h:{digest[:12]}"


def derive_source_subject_id(assignment_href: str | None) -> Optional[str]:
    match = _CLASS_ID_PATTERN.search((assignment_href or "").strip())
    return match.group(1) if match else None


def _parse_badges(summary: str | None) -> dict[str, Optional[str]]:
    """Best-effort split of "Formative, Homework /10%, Pending".

    Every field is optional; the raw string is always kept in tasks.summary,
    so a failed parse here is never lossy.
    """
    parsed: dict[str, Optional[str]] = {
        "task_type": None,
        "category": None,
        "weight": None,
        "status": None,
    }

    for raw_part in (summary or "").split(","):
        part = raw_part.strip()
        if not part:
            continue

        lowered = part.casefold()
        if lowered in _TASK_TYPES and parsed["task_type"] is None:
            parsed["task_type"] = part
        elif lowered in _TASK_STATUSES and parsed["status"] is None:
            parsed["status"] = part
        elif "/" in part:
            category, _, weight = part.partition("/")
            if parsed["category"] is None and category.strip():
                parsed["category"] = category.strip()
            if parsed["weight"] is None and weight.strip():
                parsed["weight"] = weight.strip()
        elif parsed["category"] is None:
            parsed["category"] = part

    return parsed


def _relative_attachment_path(raw_path: str, project_root: Path | None) -> str:
    """Store attachments project-relative so the vault survives a repo move."""
    candidate = Path(raw_path)
    if project_root is not None:
        try:
            return candidate.resolve().relative_to(project_root.resolve()).as_posix()
        except (ValueError, OSError):
            pass

    # Recover the tail of a stale absolute path from a previous project location.
    parts = candidate.parts
    if "data" in parts:
        index = parts.index("data")
        return Path(*parts[index:]).as_posix()

    return candidate.as_posix()


# ---------------------------------------------------------------------------
# Connection + migrations
# ---------------------------------------------------------------------------


@contextmanager
def _connect(vault_path: Path) -> Iterator[sqlite3.Connection]:
    """Open a connection and always close it.

    The API server is long-lived, so connections must not be left to the
    garbage collector the way the original module did.
    """
    connection = sqlite3.connect(vault_path)
    connection.row_factory = sqlite3.Row
    connection.execute("PRAGMA foreign_keys = ON")
    try:
        yield connection
    finally:
        connection.close()


def _create_schema(connection: sqlite3.Connection) -> None:
    connection.executescript(
        """
        CREATE TABLE IF NOT EXISTS subjects (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            source TEXT NOT NULL DEFAULT 'managebac',
            source_subject_id TEXT,
            name TEXT NOT NULL,
            ib_level TEXT,
            grade TEXT,
            created_at TEXT NOT NULL,
            updated_at TEXT NOT NULL,
            UNIQUE(source, name)
        );

        CREATE TABLE IF NOT EXISTS tasks (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            source TEXT NOT NULL DEFAULT 'managebac',
            source_task_id TEXT NOT NULL,
            subject_id INTEGER NOT NULL REFERENCES subjects(id) ON DELETE CASCADE,
            title TEXT NOT NULL,
            summary TEXT NOT NULL DEFAULT '',
            full_description TEXT NOT NULL DEFAULT '',
            source_url TEXT,
            due_date TEXT,
            task_type TEXT,
            category TEXT,
            weight TEXT,
            status TEXT,
            rubric_criteria TEXT NOT NULL DEFAULT '[]',
            parsed_cleanly INTEGER NOT NULL DEFAULT 1,
            parse_error TEXT,
            first_seen_at TEXT NOT NULL,
            last_seen_at TEXT NOT NULL,
            deleted_at TEXT,
            UNIQUE(source, source_task_id)
        );

        CREATE INDEX IF NOT EXISTS idx_tasks_subject ON tasks(subject_id);
        CREATE INDEX IF NOT EXISTS idx_tasks_source ON tasks(source, deleted_at);

        CREATE TABLE IF NOT EXISTS task_attachments (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            task_id INTEGER NOT NULL REFERENCES tasks(id) ON DELETE CASCADE,
            file_name TEXT NOT NULL,
            relative_path TEXT NOT NULL,
            extracted_text TEXT,
            created_at TEXT NOT NULL,
            UNIQUE(task_id, relative_path)
        );

        -- PLACEHOLDER: created empty for Kognity, nothing reads or writes it yet.
        -- Deliberately thin; the real shape is decided after the ingestion spike.
        CREATE TABLE IF NOT EXISTS content_blocks (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            source TEXT NOT NULL DEFAULT 'kognity',
            source_block_id TEXT,
            subject_id INTEGER NOT NULL REFERENCES subjects(id) ON DELETE CASCADE,
            topic TEXT,
            subtopic TEXT,
            title TEXT,
            body TEXT NOT NULL DEFAULT '',
            source_url TEXT,
            created_at TEXT NOT NULL,
            updated_at TEXT NOT NULL,
            UNIQUE(source, source_block_id)
        );

        CREATE TABLE IF NOT EXISTS hidden_items (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            item_type TEXT NOT NULL DEFAULT 'task',
            source TEXT NOT NULL DEFAULT 'managebac',
            item_key TEXT NOT NULL,
            alias_key TEXT,
            title TEXT NOT NULL,
            subject_name TEXT NOT NULL DEFAULT '',
            hidden_at TEXT NOT NULL,
            UNIQUE(item_type, source, item_key)
        );

        CREATE TABLE IF NOT EXISTS sync_runs (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            source TEXT NOT NULL,
            started_at TEXT NOT NULL,
            finished_at TEXT,
            status TEXT NOT NULL,
            total_items INTEGER NOT NULL DEFAULT 0,
            parse_errors INTEGER NOT NULL DEFAULT 0,
            base_url TEXT,
            used_auth_state INTEGER,
            message TEXT
        );

        CREATE INDEX IF NOT EXISTS idx_sync_runs_source ON sync_runs(source, id DESC);

        CREATE TABLE IF NOT EXISTS drafts (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            task_title TEXT NOT NULL,
            class_name TEXT NOT NULL,
            mode TEXT NOT NULL,
            created_at TEXT NOT NULL,
            content TEXT NOT NULL
        );
        """
    )


def _table_exists(connection: sqlite3.Connection, name: str) -> bool:
    row = connection.execute(
        "SELECT 1 FROM sqlite_master WHERE type='table' AND name=?",
        (name,),
    ).fetchone()
    return row is not None


def _column_names(connection: sqlite3.Connection, table: str) -> set[str]:
    return {row[1] for row in connection.execute(f"PRAGMA table_info({table})")}


def _backup_before_migration(vault_path: Path) -> None:
    if not vault_path.exists():
        return

    backup_path = vault_path.with_suffix(vault_path.suffix + ".bak-pre-v1")
    if backup_path.exists():
        return

    try:
        shutil.copy2(vault_path, backup_path)
    except OSError:
        # A missing backup must never block the migration itself.
        pass


def _migrate_legacy_hidden_tasks(connection: sqlite3.Connection) -> None:
    """Carry hidden_tasks rows over to hidden_items.

    Legacy ids were index-based and will not match the new stable ids, so each
    row also gets a content-derived alias_key. Filtering matches on either key,
    which is what keeps existing hides working across the id scheme change.
    The legacy table is intentionally left in place as a safety net.
    """
    if not _table_exists(connection, "hidden_tasks"):
        return

    rows = connection.execute(
        "SELECT task_id, task_title, class_name, hidden_at FROM hidden_tasks"
    ).fetchall()

    for row in rows:
        connection.execute(
            """
            INSERT INTO hidden_items
                (item_type, source, item_key, alias_key, title, subject_name, hidden_at)
            VALUES (?, ?, ?, ?, ?, ?, ?)
            ON CONFLICT(item_type, source, item_key) DO NOTHING
            """,
            (
                ITEM_TYPE_TASK,
                DEFAULT_SOURCE,
                row["task_id"],
                alias_key_for(row["class_name"], row["task_title"]),
                row["task_title"],
                row["class_name"],
                row["hidden_at"],
            ),
        )


_migrated_paths: set[str] = set()


def _ensure_db(vault_path: Path) -> None:
    cache_key = str(vault_path)
    if cache_key in _migrated_paths:
        return

    vault_path.parent.mkdir(parents=True, exist_ok=True)
    had_existing_db = vault_path.exists()

    with _connect(vault_path) as connection:
        version = connection.execute("PRAGMA user_version").fetchone()[0]

        if version >= SCHEMA_VERSION:
            _migrated_paths.add(cache_key)
            return

        if had_existing_db and _table_exists(connection, "drafts"):
            _backup_before_migration(vault_path)

        _create_schema(connection)

        if "task_id" not in _column_names(connection, "drafts"):
            connection.execute(
                "ALTER TABLE drafts ADD COLUMN task_id INTEGER REFERENCES tasks(id) ON DELETE SET NULL"
            )

        _migrate_legacy_hidden_tasks(connection)

        connection.execute(f"PRAGMA user_version = {SCHEMA_VERSION}")
        connection.commit()

    _migrated_paths.add(cache_key)


# ---------------------------------------------------------------------------
# Subjects
# ---------------------------------------------------------------------------


def _upsert_subject(
    connection: sqlite3.Connection,
    name: str,
    source: str,
    source_subject_id: str | None,
    timestamp: str,
) -> int:
    connection.execute(
        """
        INSERT INTO subjects (source, source_subject_id, name, created_at, updated_at)
        VALUES (?, ?, ?, ?, ?)
        ON CONFLICT(source, name) DO UPDATE SET
            source_subject_id = COALESCE(excluded.source_subject_id, subjects.source_subject_id),
            updated_at = excluded.updated_at
        """,
        (source, source_subject_id, name, timestamp, timestamp),
    )
    row = connection.execute(
        "SELECT id FROM subjects WHERE source = ? AND name = ?",
        (source, name),
    ).fetchone()
    return int(row["id"])


def list_subjects(vault_path: Path, source: str | None = None) -> list[dict[str, Any]]:
    _ensure_db(vault_path)
    query = """
        SELECT
            s.id,
            s.source,
            s.source_subject_id,
            s.name,
            s.ib_level,
            s.grade,
            s.created_at,
            s.updated_at,
            COUNT(t.id) AS task_count
        FROM subjects AS s
        LEFT JOIN tasks AS t
            ON t.subject_id = s.id AND t.deleted_at IS NULL
    """
    params: tuple[Any, ...] = ()
    if source:
        query += " WHERE s.source = ?"
        params = (source,)
    query += " GROUP BY s.id ORDER BY s.name COLLATE NOCASE ASC"

    with _connect(vault_path) as connection:
        rows = connection.execute(query, params).fetchall()

    return [dict(row) for row in rows]


# ---------------------------------------------------------------------------
# Task ingestion
# ---------------------------------------------------------------------------


def _link_orphan_drafts(connection: sqlite3.Connection) -> None:
    """Attach drafts written before the vault knew about tasks.

    Drafts keep their denormalized task_title/class_name regardless, so this
    only fills in the new foreign key where an exact match exists.
    """
    connection.execute(
        """
        UPDATE drafts
        SET task_id = (
            SELECT t.id
            FROM tasks AS t
            JOIN subjects AS s ON s.id = t.subject_id
            WHERE t.title = drafts.task_title AND s.name = drafts.class_name
            ORDER BY t.id ASC
            LIMIT 1
        )
        WHERE task_id IS NULL
          AND EXISTS (
              SELECT 1
              FROM tasks AS t
              JOIN subjects AS s ON s.id = t.subject_id
              WHERE t.title = drafts.task_title AND s.name = drafts.class_name
          )
        """
    )


def ingest_scrape_payload(
    vault_path: Path,
    payload: dict[str, Any],
    project_root: Path | None = None,
    source: str = DEFAULT_SOURCE,
) -> dict[str, int]:
    """Fold a ScrapeOutput-shaped payload into subjects/tasks/task_attachments.

    Idempotent: re-ingesting the same scrape refreshes content and last_seen_at
    without resurrecting tasks the user permanently deleted.
    """
    _ensure_db(vault_path)

    tasks = payload.get("tasks") if isinstance(payload, dict) else None
    if not isinstance(tasks, list):
        return {"subjects": 0, "tasks": 0, "attachments": 0}

    timestamp = _now()
    subject_ids: dict[str, int] = {}
    task_count = 0
    attachment_count = 0

    with _connect(vault_path) as connection:
        for task in tasks:
            if not isinstance(task, dict):
                continue

            title = str(task.get("title") or "Untitled Task").strip()
            class_name = str(task.get("class_name") or "Unknown Class").strip()
            assignment_href = task.get("assignment_href")

            if class_name not in subject_ids:
                subject_ids[class_name] = _upsert_subject(
                    connection,
                    name=class_name,
                    source=source,
                    source_subject_id=derive_source_subject_id(assignment_href),
                    timestamp=timestamp,
                )
            subject_id = subject_ids[class_name]

            source_task_id = derive_source_task_id(assignment_href, class_name, title)
            summary = str(task.get("description") or "")
            full_description = str(task.get("full_description") or "")
            badges = _parse_badges(summary)

            connection.execute(
                """
                INSERT INTO tasks (
                    source, source_task_id, subject_id, title, summary,
                    full_description, source_url, due_date,
                    task_type, category, weight, status, rubric_criteria,
                    parsed_cleanly, parse_error, first_seen_at, last_seen_at
                )
                VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
                ON CONFLICT(source, source_task_id) DO UPDATE SET
                    subject_id = excluded.subject_id,
                    title = excluded.title,
                    summary = excluded.summary,
                    full_description = excluded.full_description,
                    source_url = excluded.source_url,
                    due_date = excluded.due_date,
                    task_type = excluded.task_type,
                    category = excluded.category,
                    weight = excluded.weight,
                    status = excluded.status,
                    -- A re-scrape that finds no criteria must not wipe any
                    -- that were recovered from an attachment.
                    rubric_criteria = CASE
                        WHEN excluded.rubric_criteria = '[]' THEN tasks.rubric_criteria
                        ELSE excluded.rubric_criteria
                    END,
                    parsed_cleanly = excluded.parsed_cleanly,
                    parse_error = excluded.parse_error,
                    last_seen_at = excluded.last_seen_at
                """,
                (
                    source,
                    source_task_id,
                    subject_id,
                    title,
                    summary,
                    full_description,
                    assignment_href,
                    task.get("due_date"),
                    badges["task_type"],
                    badges["category"],
                    badges["weight"],
                    badges["status"],
                    json.dumps(extract_criteria(full_description, summary)),
                    1 if task.get("parsed_cleanly", True) else 0,
                    task.get("parse_error"),
                    timestamp,
                    timestamp,
                ),
            )
            task_count += 1

            row = connection.execute(
                "SELECT id FROM tasks WHERE source = ? AND source_task_id = ?",
                (source, source_task_id),
            ).fetchone()
            task_row_id = int(row["id"])

            for raw_path in task.get("local_attachments") or []:
                if not raw_path:
                    continue
                relative_path = _relative_attachment_path(str(raw_path), project_root)
                connection.execute(
                    """
                    INSERT INTO task_attachments
                        (task_id, file_name, relative_path, created_at)
                    VALUES (?, ?, ?, ?)
                    ON CONFLICT(task_id, relative_path) DO NOTHING
                    """,
                    (task_row_id, Path(relative_path).name, relative_path, timestamp),
                )
                attachment_count += 1

        _link_orphan_drafts(connection)
        connection.commit()

    return {
        "subjects": len(subject_ids),
        "tasks": task_count,
        "attachments": attachment_count,
    }


# ---------------------------------------------------------------------------
# Task reads
# ---------------------------------------------------------------------------


def _attachments_for_tasks(
    connection: sqlite3.Connection, task_ids: Iterable[int]
) -> dict[int, list[str]]:
    ids = list(task_ids)
    if not ids:
        return {}

    placeholders = ",".join("?" for _ in ids)
    rows = connection.execute(
        f"""
        SELECT task_id, relative_path
        FROM task_attachments
        WHERE task_id IN ({placeholders})
        ORDER BY id ASC
        """,
        ids,
    ).fetchall()

    grouped: dict[int, list[str]] = {}
    for row in rows:
        grouped.setdefault(int(row["task_id"]), []).append(row["relative_path"])
    return grouped


def list_task_attachments(vault_path: Path, task_id: int) -> list[dict[str, Any]]:
    """Attachment rows for a task, including any cached extracted text."""
    _ensure_db(vault_path)
    with _connect(vault_path) as connection:
        rows = connection.execute(
            """
            SELECT id, task_id, file_name, relative_path, extracted_text
            FROM task_attachments
            WHERE task_id = ?
            ORDER BY id ASC
            """,
            (task_id,),
        ).fetchall()

    return [dict(row) for row in rows]


def update_task_rubric_criteria(
    vault_path: Path, task_id: int, criteria: list[dict[str, Any]]
) -> list[dict[str, Any]]:
    """Merge newly found criteria into a task, returning the stored result.

    Criteria often appear only in an attached brief rather than in the page
    text, so this lets the attachment pass enrich what ingestion found.
    """
    _ensure_db(vault_path)
    with _connect(vault_path) as connection:
        row = connection.execute(
            "SELECT rubric_criteria FROM tasks WHERE id = ?", (task_id,)
        ).fetchone()
        if row is None:
            return []

        try:
            existing = json.loads(row["rubric_criteria"] or "[]")
        except (json.JSONDecodeError, TypeError):
            existing = []

        merged = merge_criteria(existing, criteria)
        if merged != existing:
            connection.execute(
                "UPDATE tasks SET rubric_criteria = ? WHERE id = ?",
                (json.dumps(merged), task_id),
            )
            connection.commit()

    return merged


def set_attachment_text(vault_path: Path, attachment_id: int, text: str) -> None:
    """Cache extracted text so a PDF is only parsed once."""
    _ensure_db(vault_path)
    with _connect(vault_path) as connection:
        connection.execute(
            "UPDATE task_attachments SET extracted_text = ? WHERE id = ?",
            (text, attachment_id),
        )
        connection.commit()


def _task_to_api_dict(row: sqlite3.Row, attachments: list[str]) -> dict[str, Any]:
    """Response shape: legacy keys the Flutter client reads, plus additive ones."""
    try:
        rubric_criteria = json.loads(row["rubric_criteria"] or "[]")
    except (json.JSONDecodeError, TypeError):
        rubric_criteria = []

    return {
        "id": row["source_task_id"],
        "title": row["title"],
        "class_name": row["subject_name"],
        "description": row["summary"],
        "due_date": row["due_date"],
        "full_description": row["full_description"],
        "assignment_href": row["source_url"],
        "local_attachments": attachments,
        "parsed_cleanly": bool(row["parsed_cleanly"]),
        "parse_error": row["parse_error"],
        "source": row["source"],
        "subject_id": row["subject_id"],
        "task_type": row["task_type"],
        "category": row["category"],
        "weight": row["weight"],
        "status": row["status"],
        "rubric_criteria": rubric_criteria,
    }


def list_tasks(
    vault_path: Path,
    source: str = DEFAULT_SOURCE,
    include_hidden: bool = False,
) -> tuple[list[dict[str, Any]], int]:
    """Return (visible_tasks, hidden_count) for a source."""
    _ensure_db(vault_path)

    with _connect(vault_path) as connection:
        rows = connection.execute(
            """
            SELECT
                t.id, t.source, t.source_task_id, t.subject_id, t.title, t.summary,
                t.full_description, t.source_url, t.due_date, t.task_type, t.category,
                t.weight, t.status, t.rubric_criteria, t.parsed_cleanly, t.parse_error,
                s.name AS subject_name
            FROM tasks AS t
            JOIN subjects AS s ON s.id = t.subject_id
            WHERE t.source = ? AND t.deleted_at IS NULL
            ORDER BY t.id ASC
            """,
            (source,),
        ).fetchall()

        hidden_rows = connection.execute(
            """
            SELECT item_key, alias_key
            FROM hidden_items
            WHERE item_type = ? AND source = ?
            """,
            (ITEM_TYPE_TASK, source),
        ).fetchall()

        attachments = _attachments_for_tasks(connection, [int(r["id"]) for r in rows])

    hidden_keys = {row["item_key"] for row in hidden_rows if row["item_key"]}
    hidden_aliases = {row["alias_key"] for row in hidden_rows if row["alias_key"]}

    visible: list[dict[str, Any]] = []
    hidden_count = 0

    for row in rows:
        alias = alias_key_for(row["subject_name"], row["title"])
        is_hidden = row["source_task_id"] in hidden_keys or alias in hidden_aliases

        if is_hidden and not include_hidden:
            hidden_count += 1
            continue

        visible.append(_task_to_api_dict(row, attachments.get(int(row["id"]), [])))

    return visible, hidden_count


def count_tasks(vault_path: Path, source: str = DEFAULT_SOURCE) -> int:
    _ensure_db(vault_path)
    with _connect(vault_path) as connection:
        row = connection.execute(
            "SELECT COUNT(*) AS total FROM tasks WHERE source = ? AND deleted_at IS NULL",
            (source,),
        ).fetchone()
    return int(row["total"])


def find_task(
    vault_path: Path, source_task_id: str, source: str = DEFAULT_SOURCE
) -> Optional[dict[str, Any]]:
    _ensure_db(vault_path)
    with _connect(vault_path) as connection:
        row = connection.execute(
            """
            SELECT t.*, s.name AS subject_name
            FROM tasks AS t
            JOIN subjects AS s ON s.id = t.subject_id
            WHERE t.source = ? AND t.source_task_id = ?
            """,
            (source, source_task_id),
        ).fetchone()
    return dict(row) if row is not None else None


def find_task_by_title(
    vault_path: Path,
    class_name: str,
    task_title: str,
    source: str = DEFAULT_SOURCE,
) -> Optional[dict[str, Any]]:
    _ensure_db(vault_path)
    with _connect(vault_path) as connection:
        rows = connection.execute(
            """
            SELECT t.*, s.name AS subject_name
            FROM tasks AS t
            JOIN subjects AS s ON s.id = t.subject_id
            WHERE t.source = ?
            """,
            (source,),
        ).fetchall()

    target = (_normalize(class_name), _normalize(task_title))
    for row in rows:
        if (_normalize(row["subject_name"]), _normalize(row["title"])) == target:
            return dict(row)
    return None


# ---------------------------------------------------------------------------
# Drafts
# ---------------------------------------------------------------------------


def save_draft(
    vault_path: Path,
    task_title: str,
    class_name: str,
    mode: str,
    created_at: str,
    content: str,
    task_id: int | None = None,
) -> None:
    _ensure_db(vault_path)

    if task_id is None:
        matched = find_task_by_title(vault_path, class_name, task_title)
        if matched is not None:
            task_id = int(matched["id"])

    with _connect(vault_path) as connection:
        connection.execute(
            """
            INSERT INTO drafts (task_id, task_title, class_name, mode, created_at, content)
            VALUES (?, ?, ?, ?, ?, ?)
            """,
            (task_id, task_title, class_name, mode, created_at, content),
        )
        connection.commit()


def list_drafts(vault_path: Path, limit: int = 200) -> list[dict[str, Any]]:
    _ensure_db(vault_path)
    with _connect(vault_path) as connection:
        rows = connection.execute(
            """
            SELECT id, task_id, task_title, class_name, mode, created_at, content
            FROM drafts
            ORDER BY datetime(created_at) DESC, id DESC
            LIMIT ?
            """,
            (limit,),
        ).fetchall()

    return [dict(row) for row in rows]


# ---------------------------------------------------------------------------
# Hidden items
# ---------------------------------------------------------------------------


def hide_item(
    vault_path: Path,
    item_key: str,
    title: str,
    subject_name: str,
    hidden_at: str,
    item_type: str = ITEM_TYPE_TASK,
    source: str = DEFAULT_SOURCE,
) -> None:
    _ensure_db(vault_path)
    with _connect(vault_path) as connection:
        connection.execute(
            """
            INSERT INTO hidden_items
                (item_type, source, item_key, alias_key, title, subject_name, hidden_at)
            VALUES (?, ?, ?, ?, ?, ?, ?)
            ON CONFLICT(item_type, source, item_key) DO UPDATE SET
                alias_key = excluded.alias_key,
                title = excluded.title,
                subject_name = excluded.subject_name,
                hidden_at = excluded.hidden_at
            """,
            (
                item_type,
                source,
                item_key,
                alias_key_for(subject_name, title),
                title,
                subject_name,
                hidden_at,
            ),
        )
        connection.commit()


def hide_task(
    vault_path: Path,
    task_id: str,
    task_title: str,
    class_name: str,
    hidden_at: str,
) -> None:
    hide_item(
        vault_path,
        item_key=task_id,
        title=task_title,
        subject_name=class_name,
        hidden_at=hidden_at,
    )


def recover_item(
    vault_path: Path,
    item_key: str,
    item_type: str = ITEM_TYPE_TASK,
    source: str = DEFAULT_SOURCE,
) -> bool:
    _ensure_db(vault_path)
    alias = None
    with _connect(vault_path) as connection:
        row = connection.execute(
            """
            SELECT alias_key FROM hidden_items
            WHERE item_type = ? AND source = ? AND item_key = ?
            """,
            (item_type, source, item_key),
        ).fetchone()
        if row is not None:
            alias = row["alias_key"]

        cursor = connection.execute(
            """
            DELETE FROM hidden_items
            WHERE item_type = ?
              AND source = ?
              AND (item_key = ? OR (alias_key IS NOT NULL AND alias_key = ?))
            """,
            (item_type, source, item_key, alias),
        )
        connection.commit()

    return cursor.rowcount > 0


def recover_task(vault_path: Path, task_id: str) -> bool:
    return recover_item(vault_path, item_key=task_id)


def permanently_delete_task(
    vault_path: Path, task_id: str, source: str = DEFAULT_SOURCE
) -> bool:
    """Soft-delete the task so a re-scrape does not resurrect it.

    Replaces the old behaviour, where "permanent delete" merely un-hid the task
    and it reappeared on the next sync.
    """
    _ensure_db(vault_path)
    timestamp = _now()

    with _connect(vault_path) as connection:
        cursor = connection.execute(
            """
            UPDATE tasks SET deleted_at = ?
            WHERE source = ? AND source_task_id = ? AND deleted_at IS NULL
            """,
            (timestamp, source, task_id),
        )
        deleted = cursor.rowcount > 0

        # The task may only exist as a hidden row (legacy hide, or already gone
        # from ManageBac); clearing that still counts as a successful delete.
        hidden_cursor = connection.execute(
            "DELETE FROM hidden_items WHERE item_type = ? AND source = ? AND item_key = ?",
            (ITEM_TYPE_TASK, source, task_id),
        )
        connection.commit()

    return deleted or hidden_cursor.rowcount > 0


def list_hidden_items(
    vault_path: Path,
    item_type: str = ITEM_TYPE_TASK,
    source: str = DEFAULT_SOURCE,
    limit: int = 500,
) -> list[dict[str, Any]]:
    _ensure_db(vault_path)
    with _connect(vault_path) as connection:
        rows = connection.execute(
            """
            SELECT item_key, alias_key, title, subject_name, hidden_at
            FROM hidden_items
            WHERE item_type = ? AND source = ?
            ORDER BY datetime(hidden_at) DESC, id DESC
            LIMIT ?
            """,
            (item_type, source, limit),
        ).fetchall()

    return [dict(row) for row in rows]


# ---------------------------------------------------------------------------
# Sync runs
# ---------------------------------------------------------------------------


def start_sync_run(vault_path: Path, source: str = DEFAULT_SOURCE) -> int:
    _ensure_db(vault_path)
    with _connect(vault_path) as connection:
        cursor = connection.execute(
            "INSERT INTO sync_runs (source, started_at, status) VALUES (?, ?, ?)",
            (source, _now(), "running"),
        )
        connection.commit()
    return int(cursor.lastrowid)


def finish_sync_run(
    vault_path: Path,
    run_id: int,
    status: str,
    total_items: int = 0,
    parse_errors: int = 0,
    base_url: str | None = None,
    used_auth_state: bool | None = None,
    message: str | None = None,
) -> None:
    _ensure_db(vault_path)
    with _connect(vault_path) as connection:
        connection.execute(
            """
            UPDATE sync_runs SET
                finished_at = ?, status = ?, total_items = ?, parse_errors = ?,
                base_url = ?, used_auth_state = ?, message = ?
            WHERE id = ?
            """,
            (
                _now(),
                status,
                total_items,
                parse_errors,
                base_url,
                None if used_auth_state is None else int(used_auth_state),
                message,
                run_id,
            ),
        )
        connection.commit()


def record_sync_run(
    vault_path: Path,
    source: str,
    started_at: str,
    status: str,
    total_items: int = 0,
    parse_errors: int = 0,
    base_url: str | None = None,
    used_auth_state: bool | None = None,
    message: str | None = None,
) -> int:
    """Insert an already-completed run with an explicit timestamp.

    Used to preserve the timestamp of a scrape that happened before the vault
    tracked sync runs, rather than stamping it with the migration time.
    """
    _ensure_db(vault_path)
    with _connect(vault_path) as connection:
        cursor = connection.execute(
            """
            INSERT INTO sync_runs (
                source, started_at, finished_at, status, total_items,
                parse_errors, base_url, used_auth_state, message
            )
            VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)
            """,
            (
                source,
                started_at,
                started_at,
                status,
                total_items,
                parse_errors,
                base_url,
                None if used_auth_state is None else int(used_auth_state),
                message,
            ),
        )
        connection.commit()
    return int(cursor.lastrowid)


def get_last_sync_run(
    vault_path: Path, source: str = DEFAULT_SOURCE
) -> Optional[dict[str, Any]]:
    _ensure_db(vault_path)
    with _connect(vault_path) as connection:
        row = connection.execute(
            """
            SELECT id, source, started_at, finished_at, status, total_items,
                   parse_errors, base_url, used_auth_state, message
            FROM sync_runs
            WHERE source = ?
            ORDER BY id DESC
            LIMIT 1
            """,
            (source,),
        ).fetchone()

    if row is None:
        return None

    record = dict(row)
    if record["used_auth_state"] is not None:
        record["used_auth_state"] = bool(record["used_auth_state"])
    return record
