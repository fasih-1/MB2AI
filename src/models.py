from __future__ import annotations

from datetime import datetime, timezone
from typing import Any, Optional

from pydantic import BaseModel, Field


# ---------------------------------------------------------------------------
# Scrape payload models
#
# These define the on-disk contract for data/tasks_raw.json and are built by
# parser.py / scraper.py. Unchanged by the vault rework: brain.py still reads
# that file, so the shape must stay stable.
# ---------------------------------------------------------------------------


class TaskItem(BaseModel):
    id: str
    title: str
    class_name: str
    description: str
    assignment_href: Optional[str] = None
    full_description: str = ""
    local_attachments: list[str] = Field(default_factory=list)
    due_date: Optional[str] = None
    parsed_cleanly: bool = True
    parse_error: Optional[str] = None


class ScrapeMetadata(BaseModel):
    scraped_at: str = Field(default_factory=lambda: datetime.now(timezone.utc).isoformat())
    base_url: str
    total_tasks: int
    parse_errors_count: int
    used_auth_state: bool


class ScrapeOutput(BaseModel):
    metadata: ScrapeMetadata
    tasks: list[TaskItem]


# ---------------------------------------------------------------------------
# Vault models
#
# Mirror the SQLite schema in vault.py. `source` on every ingested entity is
# what keeps the model multi-source-ready ahead of the Kognity work.
# ---------------------------------------------------------------------------


class Subject(BaseModel):
    id: int
    source: str = "managebac"
    source_subject_id: Optional[str] = None
    name: str
    ib_level: Optional[str] = None
    grade: Optional[str] = None
    created_at: Optional[str] = None
    updated_at: Optional[str] = None
    task_count: int = 0


class TaskAttachment(BaseModel):
    id: Optional[int] = None
    task_id: Optional[int] = None
    file_name: str
    relative_path: str
    extracted_text: Optional[str] = None
    created_at: Optional[str] = None


class Task(BaseModel):
    id: int
    source: str = "managebac"
    source_task_id: str
    subject_id: int
    title: str
    summary: str = ""
    full_description: str = ""
    source_url: Optional[str] = None
    due_date: Optional[str] = None
    task_type: Optional[str] = None
    category: Optional[str] = None
    weight: Optional[str] = None
    status: Optional[str] = None
    rubric_criteria: list[Any] = Field(default_factory=list)
    parsed_cleanly: bool = True
    parse_error: Optional[str] = None
    first_seen_at: Optional[str] = None
    last_seen_at: Optional[str] = None
    deleted_at: Optional[str] = None


class TaskRead(BaseModel):
    """The /tasks response item.

    `id`, `title`, `class_name`, `description` and `due_date` are the keys the
    Flutter TaskSummary model reads; everything after them is additive, so the
    existing UI keeps working untouched.
    """

    id: str
    title: str
    class_name: str
    description: str = ""
    due_date: Optional[str] = None
    full_description: str = ""
    assignment_href: Optional[str] = None
    local_attachments: list[str] = Field(default_factory=list)
    parsed_cleanly: bool = True
    parse_error: Optional[str] = None
    source: str = "managebac"
    subject_id: Optional[int] = None
    task_type: Optional[str] = None
    category: Optional[str] = None
    weight: Optional[str] = None
    status: Optional[str] = None
    rubric_criteria: list[Any] = Field(default_factory=list)


class ContentBlock(BaseModel):
    """Placeholder for Kognity content. Nothing populates this yet."""

    id: int
    source: str = "kognity"
    source_block_id: Optional[str] = None
    subject_id: int
    topic: Optional[str] = None
    subtopic: Optional[str] = None
    title: Optional[str] = None
    body: str = ""
    source_url: Optional[str] = None
    created_at: Optional[str] = None
    updated_at: Optional[str] = None


class Draft(BaseModel):
    id: int
    task_id: Optional[int] = None
    task_title: str
    class_name: str
    mode: str
    created_at: str
    content: str


class HiddenItem(BaseModel):
    item_key: str
    alias_key: Optional[str] = None
    title: str
    subject_name: str = ""
    hidden_at: str
    item_type: str = "task"
    source: str = "managebac"


class SyncRun(BaseModel):
    id: int
    source: str
    started_at: str
    finished_at: Optional[str] = None
    status: str
    total_items: int = 0
    parse_errors: int = 0
    base_url: Optional[str] = None
    used_auth_state: Optional[bool] = None
    message: Optional[str] = None
