from __future__ import annotations

import asyncio
from contextlib import asynccontextmanager
import json
import re
from functools import lru_cache
from pathlib import Path
from typing import Any

from fastapi import BackgroundTasks, FastAPI, File, Form, HTTPException, UploadFile, WebSocket, WebSocketDisconnect
from fastapi.responses import PlainTextResponse

from .brain import generate_drafts_from_tasks
from .config import Settings, load_settings
from .logger import setup_logger
from .scraper import Scraper
from .text_extractor import extract_text_from_attachment
from .vault import list_drafts

_log_queue: asyncio.Queue[str] | None = None


def _get_log_queue() -> asyncio.Queue[str]:
    global _log_queue
    if _log_queue is None:
        _log_queue = asyncio.Queue(maxsize=500)
    return _log_queue


@asynccontextmanager
async def lifespan(_: FastAPI):
    settings = _get_settings()
    queue = _get_log_queue()
    loop = asyncio.get_running_loop()
    setup_logger(settings.project_root, log_queue=queue, event_loop=loop)
    yield


app = FastAPI(title="MB2AI API", version="0.1.0", lifespan=lifespan)


def _sanitize_name(value: str) -> str:
    cleaned = re.sub(r"[<>:\"/\\|?*]+", "_", (value or "").strip())
    cleaned = re.sub(r"\s+", " ", cleaned).strip().strip(".")
    return cleaned[:120] or "untitled"


@lru_cache(maxsize=1)
def _get_settings() -> Settings:
    return load_settings()


@lru_cache(maxsize=1)
def _get_logger():
    settings = _get_settings()
    return setup_logger(settings.project_root)


def _read_tasks_payload(tasks_path: Path) -> dict[str, Any]:
    if not tasks_path.exists():
        raise HTTPException(status_code=404, detail="tasks_raw.json was not found.")

    try:
        with tasks_path.open("r", encoding="utf-8") as handle:
            payload = json.load(handle)
    except json.JSONDecodeError as exc:
        raise HTTPException(status_code=500, detail=f"Invalid tasks JSON: {exc}") from exc

    if not isinstance(payload, dict):
        raise HTTPException(status_code=500, detail="Expected object payload in tasks_raw.json.")

    return payload


def _resolve_draft_path(settings: Settings, class_name: str, task_title: str) -> Path:
    safe_class = _sanitize_name(class_name)
    safe_title = _sanitize_name(task_title)
    return settings.project_root / "data" / "pending_review" / safe_class / f"{safe_title}.md"


def _run_scrape_job() -> None:
    settings = load_settings()
    logger = setup_logger(settings.project_root)
    scraper = Scraper(settings=settings, logger=logger)

    try:
        output_path = asyncio.run(scraper.run())
        logger.info("API_SCRAPE_COMPLETE output=%s", output_path)
    except Exception:
        logger.exception("API_SCRAPE_FAILED")


def _run_generate_job(
    mode: str = "tutor",
    class_name: str | None = None,
    task_title: str | None = None,
    custom_instructions: str | None = "",
    source_document_context: str | None = "",
) -> None:
    settings = load_settings()
    logger = setup_logger(settings.project_root)
    output_base = settings.project_root / "data" / "pending_review"

    try:
        summary = generate_drafts_from_tasks(
            tasks_path=settings.tasks_output_path,
            output_base=output_base,
            api_key=settings.groq_api_key,
            model_name=settings.groq_model,
            mode=mode,
            class_name=class_name,
            task_title=task_title,
            custom_instructions=custom_instructions,
            source_document_context=source_document_context,
            vault_db_path=settings.vault_db_path,
            logger=logger,
        )
        logger.info(
            "API_GENERATE_COMPLETE generated=%s skipped=%s failed=%s mode=%s class=%s title=%s",
            summary["generated"],
            summary["skipped"],
            summary["failed"],
            mode,
            class_name,
            task_title,
        )
    except Exception:
        logger.exception("API_GENERATE_FAILED")


@app.get("/tasks")
def get_tasks() -> dict[str, Any]:
    settings = _get_settings()
    return _read_tasks_payload(settings.tasks_output_path)


@app.get("/tasks/{class_name}/{task_title}/draft", response_class=PlainTextResponse)
def get_task_draft(class_name: str, task_title: str) -> str:
    settings = _get_settings()
    draft_path = _resolve_draft_path(settings, class_name, task_title)

    if not draft_path.exists():
        raise HTTPException(status_code=404, detail="Draft file was not found.")

    return draft_path.read_text(encoding="utf-8")


@app.get("/vault")
def get_vault() -> dict[str, Any]:
    settings = _get_settings()
    drafts = list_drafts(settings.vault_db_path)
    return {"drafts": drafts}


@app.post("/scrape")
def start_scrape(background_tasks: BackgroundTasks) -> dict[str, str]:
    background_tasks.add_task(_run_scrape_job)
    return {"status": "Scraping started"}


@app.post("/generate")
async def start_generate(
    background_tasks: BackgroundTasks,
    mode: str = Form("tutor"),
    class_name: str | None = Form(None),
    task_title: str | None = Form(None),
    custom_instructions: str = Form(""),
    attachment: UploadFile | None = File(None),
) -> dict[str, str | None]:
    source_document_context = ""
    if attachment is not None:
        attachment_bytes = await attachment.read()
        source_document_context = extract_text_from_attachment(
            attachment.filename or "",
            attachment_bytes,
        )

    background_tasks.add_task(
        _run_generate_job,
        mode,
        class_name,
        task_title,
        custom_instructions,
        source_document_context,
    )
    return {
        "status": "Generation started",
        "mode": mode,
        "class_name": class_name,
        "task_title": task_title,
    }


@app.websocket("/ws/logs")
async def ws_logs(websocket: WebSocket) -> None:
    await websocket.accept()
    queue = _get_log_queue()

    try:
        while True:
            log_message = await queue.get()
            await websocket.send_text(log_message)
    except WebSocketDisconnect:
        return
    except RuntimeError:
        return
