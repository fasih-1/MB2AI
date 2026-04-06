from __future__ import annotations

import asyncio
import json
import logging
import re
from datetime import datetime
from pathlib import Path
from typing import Awaitable, Callable
from urllib.parse import urljoin

from playwright.async_api import BrowserContext, Error, Page, TimeoutError, async_playwright

from .config import Settings
from .models import ScrapeMetadata, ScrapeOutput
from .parser import parse_tasks
from .selectors import SELECTORS


class TaskContainerNotFoundError(RuntimeError):
    pass


class Scraper:
    def __init__(self, settings: Settings, logger: logging.Logger) -> None:
        self.settings = settings
        self.logger = logger

    async def _with_retry(self, label: str, action: Callable[[], Awaitable[None]]) -> None:
        attempts = self.settings.retry_attempts
        backoff = self.settings.retry_backoff_seconds

        for attempt in range(1, attempts + 1):
            try:
                await action()
                return
            except (TimeoutError, Error) as exc:
                self.logger.warning(
                    "%s failed on attempt %s/%s: %s", label, attempt, attempts, exc
                )
                if attempt == attempts:
                    raise
                await asyncio.sleep(backoff * attempt)

    async def _is_logged_in(self, page: Page) -> bool:
        current_url = page.url.lower()
        if "login" in current_url:
            return False

        login_indicators = [
            "input[type='password']",
            "button:has-text('Log in')",
            "button:has-text('Sign in')",
        ]
        for selector in login_indicators:
            if await page.query_selector(selector):
                return False
        return True

    async def _perform_login(self, page: Page) -> None:
        username_selectors = [
            "input[name='username']",
            "input[type='email']",
            "input[id*='username']",
        ]
        password_selectors = [
            "input[name='password']",
            "input[type='password']",
        ]

        username_input = None
        for selector in username_selectors:
            username_input = await page.query_selector(selector)
            if username_input:
                break

        password_input = None
        for selector in password_selectors:
            password_input = await page.query_selector(selector)
            if password_input:
                break

        if not username_input or not password_input:
            raise RuntimeError("Could not find login form fields.")

        await username_input.fill(self.settings.username)
        await password_input.fill(self.settings.password)

        submit_selectors = [
            "button[type='submit']",
            "button:has-text('Log in')",
            "button:has-text('Sign in')",
            "input[type='submit']",
        ]

        for selector in submit_selectors:
            submit = await page.query_selector(selector)
            if submit:
                await submit.click()
                return

        raise RuntimeError("Could not find a login submit button.")

    async def _dismiss_post_login_popups(self, page: Page) -> None:
        # Keep this non-blocking: only a short best-effort pass for known popup actions.
        popup_selectors = [
            "button:has-text('Accept')",
            "button:has-text('Accept All Cookies')",
            "button:has-text('Agree')",
            "button:has-text('Close')",
        ]
        for selector in popup_selectors:
            try:
                button = page.locator(selector).first
                await button.wait_for(state="visible", timeout=1000)
                await button.click(timeout=1500)
                self.logger.info("POPUP_DISMISSED selector=%s", selector)
            except Exception:
                # Popup not present or not actionable; continue smoothly.
                continue

    async def _ensure_logged_in(self, context: BrowserContext, page: Page) -> None:
        async def step() -> None:
            await page.goto(self.settings.base_url, wait_until="domcontentloaded")
            if await self._is_logged_in(page):
                self.logger.info("LOGIN_REUSE_SUCCESS")
                return

            self.logger.info("LOGIN_START")
            await self._perform_login(page)
            try:
                await self._dismiss_post_login_popups(page)
            except Exception as exc:
                self.logger.info("POPUP_DISMISS_SKIPPED reason=%s", exc)
            await page.wait_for_load_state("networkidle")
            await page.wait_for_timeout(1500)

            if not await self._is_logged_in(page):
                raise RuntimeError("Login appears unsuccessful. Check credentials and URL.")

            self.logger.info("LOGIN_SUCCESS")
            self.settings.auth_state_path.parent.mkdir(parents=True, exist_ok=True)
            await context.storage_state(path=str(self.settings.auth_state_path))

        await self._with_retry("LOGIN_FLOW", step)

    async def _open_context(self):
        playwright = await async_playwright().start()
        browser = await playwright.chromium.launch(headless=self.settings.headless)

        context_kwargs = {
            "viewport": {"width": 1400, "height": 900},
        }

        used_auth_state = False
        if self.settings.auth_state_path.exists():
            context_kwargs["storage_state"] = str(self.settings.auth_state_path)
            used_auth_state = True

        context = await browser.new_context(**context_kwargs)
        context.set_default_timeout(self.settings.action_timeout_ms)
        context.set_default_navigation_timeout(self.settings.navigation_timeout_ms)

        return playwright, browser, context, used_auth_state

    async def _navigate_to_tasks(self, page: Page) -> None:
        async def step() -> None:
            tasks_candidates = [
                f"{self.settings.base_url.rstrip('/')}/tasks_and_deadlines",
                f"{self.settings.base_url.rstrip('/')}/tasks",
                f"{self.settings.base_url.rstrip('/')}/deadlines",
            ]

            for url in tasks_candidates:
                await page.goto(url, wait_until="domcontentloaded")
                await page.wait_for_timeout(1500)
                if "tasks" in page.url.lower() or "deadline" in page.url.lower():
                    return

            nav_links = [
                "a:has-text('Tasks & Deadlines')",
                "a:has-text('Tasks')",
                "a:has-text('Deadlines')",
            ]
            for selector in nav_links:
                link = await page.query_selector(selector)
                if link:
                    await link.click()
                    await page.wait_for_load_state("networkidle")
                    return

            raise RuntimeError("Could not navigate to Tasks & Deadlines page.")

        await self._with_retry("NAVIGATE_TASKS", step)

    async def _wait_for_task_container(self, page: Page) -> None:
        try:
            await page.wait_for_selector(SELECTORS.task_card_selector, timeout=5000)
            self.logger.info("TASK_CONTAINER_READY selector=%s", SELECTORS.task_card_selector)
            return
        except TimeoutError:
            pass

        last_timeout: TimeoutError | None = None
        for selector in SELECTORS.task_containers:
            try:
                await page.wait_for_selector(selector, timeout=4000)
                self.logger.info("TASK_CONTAINER_READY selector=%s", selector)
                return
            except TimeoutError as exc:
                last_timeout = exc
                continue
        raise TaskContainerNotFoundError("Task container not found after login/navigation.") from last_timeout

    async def _save_zero_tasks_debug_artifacts(self, page: Page) -> None:
        data_dir = self.settings.tasks_output_path.parent
        data_dir.mkdir(parents=True, exist_ok=True)

        screenshot_path = data_dir / "debug_zero_tasks.png"
        html_path = data_dir / "debug_page.html"

        await page.screenshot(path=str(screenshot_path), full_page=True)
        html_content = await page.content()
        html_path.write_text(html_content, encoding="utf-8")

        self.logger.warning(
            "ZERO_TASKS_DEBUG_ARTIFACTS screenshot=%s html=%s timestamp=%s",
            screenshot_path,
            html_path,
            datetime.utcnow().isoformat() + "Z",
        )

    @staticmethod
    def _sanitize_filename(value: str) -> str:
        sanitized = re.sub(r'[<>:"/\\|?*]+', "_", value).strip().strip(".")
        return sanitized[:120] or "untitled_task"

    def _build_assignment_url(self, href: str | None) -> str | None:
        if not href:
            return None
        return urljoin(f"{self.settings.base_url.rstrip('/')}/", href)

    async def _expand_assignment_description(self, page: Page) -> None:
        expander_selectors = [
            "button:has-text('Show More')",
            "a:has-text('Show More')",
            "button:has-text('Read More')",
            "a:has-text('Read More')",
            "button:has-text('Expand')",
            "a:has-text('Expand')",
        ]
        for selector in expander_selectors:
            try:
                control = page.locator(selector).first
                await control.wait_for(state="visible", timeout=800)
                await control.click(timeout=1500)
                self.logger.info("DESCRIPTION_EXPANDED selector=%s", selector)
                return
            except Exception:
                continue

    async def _extract_full_description(self, page: Page) -> str:
        description_selectors = [
            ".f-assignment__description .fr-view",
            ".f-assignment__description",
            ".fr-view",
            ".rich-text",
            "[data-testid='task-description']",
            ".assignment-description",
            ".f-content",
        ]
        for selector in description_selectors:
            block = page.locator(selector).first
            if await block.count() == 0:
                continue
            text = (await block.inner_text()).strip()
            if text:
                return text
        return ""

    async def _download_attachments_for_task(self, page: Page, task_title: str) -> list[str]:
        base_dir = self.settings.tasks_output_path.parent / "attachments" / self._sanitize_filename(task_title)
        base_dir.mkdir(parents=True, exist_ok=True)

        attachment_selectors = [
            ".attachments a[href]",
            "a[download]",
            "a[href*='attachment']",
            "a[href*='download']",
            "a[href*='file']",
        ]

        downloaded_paths: list[str] = []
        seen_keys: set[str] = set()

        for selector in attachment_selectors:
            links = await page.locator(selector).all()
            for link in links:
                href = (await link.get_attribute("href") or "").strip()
                text = (await link.inner_text()).strip()
                key = f"{href}|{text}"
                if key in seen_keys:
                    continue
                seen_keys.add(key)

                try:
                    async with page.expect_download(timeout=5000) as download_info:
                        await link.click()
                    download = await download_info.value

                    suggested_name = download.suggested_filename or "attachment.bin"
                    target_path = base_dir / suggested_name
                    if target_path.exists():
                        timestamp = datetime.utcnow().strftime("%Y%m%d%H%M%S")
                        target_path = base_dir / f"{target_path.stem}_{timestamp}{target_path.suffix}"

                    await download.save_as(str(target_path))
                    downloaded_paths.append(str(target_path))
                    self.logger.info("ATTACHMENT_DOWNLOADED task=%s file=%s", task_title, target_path)
                except Exception as exc:
                    self.logger.info(
                        "ATTACHMENT_DOWNLOAD_SKIPPED task=%s href=%s reason=%s",
                        task_title,
                        href,
                        exc,
                    )

        return downloaded_paths

    async def _deep_scrape_tasks(self, page: Page, tasks) -> None:
        for task in tasks:
            task_url = self._build_assignment_url(task.assignment_href)
            if not task_url:
                self.logger.info("DEEP_SCRAPE_SKIP_NO_HREF task=%s", task.title)
                task.full_description = ""
                task.local_attachments = []
                continue

            try:
                await page.goto(task_url, wait_until="domcontentloaded")
                await page.wait_for_load_state("networkidle")

                try:
                    await self._expand_assignment_description(page)
                except Exception as exc:
                    self.logger.info("DESCRIPTION_EXPAND_SKIPPED task=%s reason=%s", task.title, exc)

                task.full_description = await self._extract_full_description(page)
                task.local_attachments = await self._download_attachments_for_task(page, task.title)

                self.logger.info(
                    "DEEP_SCRAPE_DONE task=%s description_chars=%s attachments=%s",
                    task.title,
                    len(task.full_description or ""),
                    len(task.local_attachments),
                )
            except Exception as exc:
                self.logger.warning("DEEP_SCRAPE_FAILED task=%s reason=%s", task.title, exc)
                task.full_description = task.full_description or ""
                task.local_attachments = task.local_attachments or []

    async def run(self) -> Path:
        playwright, browser, context, used_auth_state = await self._open_context()

        try:
            page = await context.new_page()
            await self._ensure_logged_in(context, page)
            await self._navigate_to_tasks(page)
            try:
                await self._wait_for_task_container(page)
            except TaskContainerNotFoundError as exc:
                self.logger.warning("TASK_CONTAINER_MISSING: %s", exc)
                await self._save_zero_tasks_debug_artifacts(page)

                if self.settings.debug_mode:
                    self.logger.info(
                        "DEBUG_MODE_INSPECTOR opening Playwright Inspector via page.pause()."
                    )
                    try:
                        await page.pause()
                    except Exception as pause_exc:
                        self.logger.warning("DEBUG_MODE_INSPECTOR_UNAVAILABLE: %s", pause_exc)

                payload = ScrapeOutput(
                    metadata=ScrapeMetadata(
                        base_url=self.settings.base_url,
                        total_tasks=0,
                        parse_errors_count=0,
                        used_auth_state=used_auth_state,
                    ),
                    tasks=[],
                )

                self.settings.tasks_output_path.parent.mkdir(parents=True, exist_ok=True)
                with self.settings.tasks_output_path.open("w", encoding="utf-8") as handle:
                    json.dump(payload.model_dump(), handle, indent=2, ensure_ascii=False)

                await context.storage_state(path=str(self.settings.auth_state_path))
                self.logger.info(
                    "SCRAPE_PARTIAL_SUCCESS total_tasks=0 output=%s (container not found)",
                    self.settings.tasks_output_path,
                )
                return self.settings.tasks_output_path

            tasks = await parse_tasks(page)
            await self._deep_scrape_tasks(page, tasks)
            parse_errors = len([t for t in tasks if not t.parsed_cleanly])

            if len(tasks) == 0:
                await self._save_zero_tasks_debug_artifacts(page)

            payload = ScrapeOutput(
                metadata=ScrapeMetadata(
                    base_url=self.settings.base_url,
                    total_tasks=len(tasks),
                    parse_errors_count=parse_errors,
                    used_auth_state=used_auth_state,
                ),
                tasks=tasks,
            )

            self.settings.tasks_output_path.parent.mkdir(parents=True, exist_ok=True)
            with self.settings.tasks_output_path.open("w", encoding="utf-8") as handle:
                json.dump(payload.model_dump(), handle, indent=2, ensure_ascii=False)

            await context.storage_state(path=str(self.settings.auth_state_path))
            self.logger.info(
                "SCRAPE_SUCCESS total_tasks=%s parse_errors=%s output=%s",
                len(tasks),
                parse_errors,
                self.settings.tasks_output_path,
            )
            return self.settings.tasks_output_path
        finally:
            await context.close()
            await browser.close()
            await playwright.stop()
