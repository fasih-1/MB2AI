from __future__ import annotations

from datetime import datetime, timezone
from typing import Optional

from pydantic import BaseModel, Field


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
