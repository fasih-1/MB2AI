from __future__ import annotations

from typing import Optional

from playwright.async_api import Locator, Page

from .models import TaskItem
from .selectors import SELECTORS
from .vault import derive_source_task_id


async def _first_text(node: Locator, selectors: tuple[str, ...]) -> Optional[str]:
    for selector in selectors:
        match = node.locator(selector).first
        if await match.count() == 0:
            continue
        text = (await match.inner_text()).strip()
        if text:
            return text
    return None


async def _first_href(node: Locator, selectors: tuple[str, ...]) -> Optional[str]:
    for selector in selectors:
        match = node.locator(selector).first
        if await match.count() == 0:
            continue
        href = await match.get_attribute("href")
        if href and href.strip():
            return href.strip()
    return None


async def _badge_labels_text(node: Locator) -> str:
    badges = await node.locator(".f-tile__description .badge-label").all()
    if not badges:
        return ""

    values: list[str] = []
    for badge in badges:
        text = (await badge.inner_text()).strip()
        if text:
            values.append(text)

    return ", ".join(values)


def _task_id_from_content(
    title: str, class_name: str, assignment_href: Optional[str]
) -> str:
    """Stable task id.

    Delegates to the vault so the scrape payload and the database agree on
    identity. Previously this hashed in the row's list index, which meant every
    id changed whenever ManageBac re-ordered the dashboard.
    """
    return derive_source_task_id(assignment_href, class_name, title)


async def parse_tasks(page: Page) -> list[TaskItem]:
    rows = await page.locator(SELECTORS.task_card_selector).all()

    if not rows:
        for selector in SELECTORS.task_rows:
            rows = await page.locator(selector).all()
            if rows:
                break

    tasks: list[TaskItem] = []
    for idx, row in enumerate(rows, start=1):
        title = await _first_text(row, (".f-tile__title-link",))
        assignment_href = await _first_href(row, (".f-tile__title-link", "a[href]"))
        class_name = await _first_text(row, (".f-tile__description a.link-dark",))
        due_date = await _first_text(row, (".f-tile__description span:has(.fi-clock)",))
        description = await _badge_labels_text(row)

        if not title:
            title = await _first_text(row, SELECTORS.title)
        if not class_name:
            class_name = await _first_text(row, SELECTORS.class_name)
        if not due_date:
            due_date = await _first_text(row, SELECTORS.due_date)
        if not description:
            description = await _first_text(row, SELECTORS.description) or ""

        if due_date:
            due_date = due_date.lstrip()

        parse_error = None
        parsed_cleanly = True

        if not title:
            title = f"Untitled Task {idx}"
            parsed_cleanly = False
            parse_error = "Missing title"

        if not class_name:
            class_name = "Unknown Class"
            parsed_cleanly = False
            parse_error = (parse_error + "; Missing class name") if parse_error else "Missing class name"

        if not description:
            description = ""

        task_id = _task_id_from_content(title, class_name, assignment_href)

        tasks.append(
            TaskItem(
                id=task_id,
                title=title,
                class_name=class_name,
                description=description,
                assignment_href=assignment_href,
                due_date=due_date,
                parsed_cleanly=parsed_cleanly,
                parse_error=parse_error,
            )
        )

    return tasks
