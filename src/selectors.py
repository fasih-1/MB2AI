from __future__ import annotations

from dataclasses import dataclass


@dataclass(frozen=True)
class SelectorBundle:
    task_card_selector: str
    task_containers: tuple[str, ...]
    task_rows: tuple[str, ...]
    title: tuple[str, ...]
    class_name: tuple[str, ...]
    description: tuple[str, ...]
    due_date: tuple[str, ...]


SELECTORS = SelectorBundle(
    task_card_selector=".f-tile.f-tile--inline.f-task-tile",
    task_containers=(
        ".f-tile.f-tile--inline.f-task-tile",
        "[data-testid='tasks-list']",
        "[data-testid='task-list']",
        ".tasks-container",
        "section:has([data-testid='task-card'])",
        "main:has([data-task-id])",
    ),
    task_rows=(
        "[data-testid='task-card']",
        "[data-task-id]",
        "tr.task, tr.assignment",
        "div.task-item, div.assignment-item",
    ),
    title=(
        ".f-tile__title-link",
        "a[href]",
        "[data-testid='task-title']",
        ".task-title",
        "h3, h4",
    ),
    class_name=(
        ".f-tile__description a.link-dark",
        ".f-task-tile__meta",
        ".f-task-tile__class",
        "[data-testid='class-name']",
        ".class-name",
        ".course-name",
        ".subject",
    ),
    description=(
        ".f-tile__description .badge-label",
        ".f-task-tile__description",
        ".f-task-tile__instructions",
        "[data-testid='task-description']",
        ".description",
        ".instructions",
        "p",
    ),
    due_date=(
        ".f-tile__description span:has(.fi-clock)",
        ".f-task-tile__date",
        ".f-task-tile__due-date",
        "[data-testid='due-date']",
        ".due-date",
        "time",
        ".deadline",
    ),
)
