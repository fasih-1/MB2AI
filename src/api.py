from __future__ import annotations

import asyncio
from contextlib import asynccontextmanager
from datetime import datetime, timezone
import json
import re
from functools import lru_cache
from pathlib import Path
from typing import Any

from fastapi import BackgroundTasks, FastAPI, File, Form, HTTPException, Query, UploadFile, WebSocket, WebSocketDisconnect
from fastapi.responses import PlainTextResponse
from pydantic import BaseModel

from .brain import generate_drafts_from_tasks
from .config import Settings, load_settings
from .logger import setup_logger
from .providers import NoProviderAvailableError, build_router
from .rubric import extract_criteria
from .scraper import Scraper
from .tls import enable_system_trust_store
from .text_extractor import extract_text_from_attachment, extract_text_from_path
from .vault import (
    DEFAULT_SOURCE,
    KNOWN_SOURCES,
    count_tasks,
    find_task_by_title,
    get_last_sync_run,
    hide_task,
    ingest_scrape_payload,
    list_drafts,
    list_hidden_items,
    list_subjects,
    list_task_attachments,
    list_tasks,
    permanently_delete_task,
    recover_task,
    record_sync_run,
    set_attachment_text,
    update_task_rubric_criteria,
)

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
    logger = setup_logger(settings.project_root, log_queue=queue, event_loop=loop)
    # Before any outbound HTTPS: local TLS-scanning software would otherwise
    # make every LLM call fail certificate verification.
    enable_system_trust_store(logger)
    _backfill_vault_from_json(settings, logger)
    yield


app = FastAPI(title="MB2AI API", version="0.2.0", lifespan=lifespan)


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


def _backfill_vault_from_json(settings: Settings, logger) -> None:
    """One-time seed of the vault from the last scrape on disk.

    /tasks now reads SQLite, so a vault that predates the rework would look
    empty until the next scrape. Runs only while the tasks table is empty.
    """
    try:
        if count_tasks(settings.vault_db_path) > 0:
            return

        tasks_path = settings.tasks_output_path
        if not tasks_path.exists():
            return

        with tasks_path.open("r", encoding="utf-8") as handle:
            payload = json.load(handle)

        counts = ingest_scrape_payload(
            settings.vault_db_path,
            payload,
            project_root=settings.project_root,
        )

        # Preserve the original scrape timestamp rather than stamping the
        # backfill time, so /tasks metadata is accurate straight after upgrade.
        metadata = payload.get("metadata") if isinstance(payload, dict) else None
        if isinstance(metadata, dict) and counts["tasks"]:
            record_sync_run(
                settings.vault_db_path,
                source=DEFAULT_SOURCE,
                started_at=metadata.get("scraped_at") or datetime.now(timezone.utc).isoformat(),
                status="backfill",
                total_items=int(metadata.get("total_tasks") or counts["tasks"]),
                parse_errors=int(metadata.get("parse_errors_count") or 0),
                base_url=metadata.get("base_url"),
                used_auth_state=metadata.get("used_auth_state"),
                message="seeded from data/tasks_raw.json",
            )

        logger.info(
            "VAULT_BACKFILL subjects=%s tasks=%s attachments=%s source=%s",
            counts["subjects"],
            counts["tasks"],
            counts["attachments"],
            tasks_path,
        )
    except Exception:
        logger.exception("VAULT_BACKFILL_FAILED")


def _resolve_source(source: str) -> str:
    normalized = (source or DEFAULT_SOURCE).strip().lower()
    if normalized not in KNOWN_SOURCES:
        raise HTTPException(
            status_code=400,
            detail=f"Unknown source '{source}'. Expected one of: {', '.join(KNOWN_SOURCES)}.",
        )
    return normalized


def _never_run_status(source: str) -> str:
    """A source with no sync history: only ManageBac has an ingestion worker."""
    return "never_run" if source == DEFAULT_SOURCE else "not_configured"


def _build_tasks_metadata(
    settings: Settings, source: str, visible_count: int, hidden_count: int
) -> dict[str, Any]:
    """Metadata block for /tasks, sourced from sync_runs.

    Keeps the keys the old tasks_raw.json metadata carried so nothing
    downstream has to change.
    """
    last_run = get_last_sync_run(settings.vault_db_path, source=source)

    return {
        "source": source,
        "scraped_at": (last_run or {}).get("finished_at") or (last_run or {}).get("started_at"),
        "base_url": (last_run or {}).get("base_url"),
        "used_auth_state": (last_run or {}).get("used_auth_state"),
        "sync_status": (last_run or {}).get("status") or _never_run_status(source),
        "parse_errors_count": (last_run or {}).get("parse_errors", 0),
        "total_tasks": visible_count + hidden_count,
        "visible_tasks": visible_count,
        "hidden_tasks": hidden_count,
    }


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


def _scraped_attachment_context(
    settings: Settings, class_name: str | None, task_title: str | None, logger
) -> str:
    """Text from the attachments the scraper already downloaded for a task.

    The scraper saves assignment attachments to disk and records them, but
    generation previously ignored them and made the user re-upload the same
    file by hand. Extracted text is cached on the row so a PDF is parsed once.

    Unreadable or unsupported files (the scraper also grabs .docx and images)
    are skipped rather than failing the run.
    """
    if not class_name or not task_title:
        return ""

    task = find_task_by_title(settings.vault_db_path, class_name, task_title)
    if task is None:
        return ""

    sections: list[str] = []
    for attachment in list_task_attachments(settings.vault_db_path, int(task["id"])):
        text = (attachment["extracted_text"] or "").strip()

        if not text:
            path = settings.project_root / attachment["relative_path"]
            text = extract_text_from_path(path).strip()
            if text:
                try:
                    set_attachment_text(
                        settings.vault_db_path, int(attachment["id"]), text
                    )
                except Exception as exc:
                    logger.warning("ATTACHMENT_CACHE_FAILED reason=%s", exc)

        if text:
            sections.append(f"--- {attachment['file_name']} ---\n{text}")
        else:
            logger.info(
                "ATTACHMENT_SKIPPED file=%s reason=no_extractable_text",
                attachment["file_name"],
            )

    context = "\n\n".join(sections)

    # Criteria are often named only in the attached brief, not in the page text
    # ingestion sees, so enrich the task from what was just read.
    if context:
        try:
            criteria = extract_criteria(context)
            if criteria:
                stored = update_task_rubric_criteria(
                    settings.vault_db_path, int(task["id"]), criteria
                )
                logger.info(
                    "TASK_CRITERIA_FROM_ATTACHMENT title=%s criteria=%s",
                    task_title,
                    [c["letter"] for c in stored],
                )
        except Exception as exc:
            logger.warning("TASK_CRITERIA_UPDATE_FAILED reason=%s", exc)

    return context


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
        # Generation reads the vault, so it honours hides and permanent deletes
        # rather than regenerating from whatever the last scrape left on disk.
        tasks, _ = list_tasks(settings.vault_db_path)

        # An explicit upload wins; otherwise fall back to what the scraper
        # already downloaded for this task.
        if not (source_document_context or "").strip():
            source_document_context = _scraped_attachment_context(
                settings, class_name, task_title, logger
            )
            if source_document_context:
                logger.info(
                    "GEN_ATTACHMENT_CONTEXT source=scraped chars=%s class=%s title=%s",
                    len(source_document_context),
                    class_name,
                    task_title,
                )

        summary = generate_drafts_from_tasks(
            tasks=tasks,
            output_base=output_base,
            provider_router=build_router(settings, logger),
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
    except NoProviderAvailableError as exc:
        logger.error("API_GENERATE_NO_PROVIDER reason=%s", exc)
    except Exception:
        logger.exception("API_GENERATE_FAILED")


class HideTaskRequest(BaseModel):
    task_id: str
    task_title: str
    class_name: str


class TaskMutationRequest(BaseModel):
    task_id: str


@app.get("/tasks")
def get_tasks(source: str = Query(DEFAULT_SOURCE)) -> dict[str, Any]:
    settings = _get_settings()
    resolved_source = _resolve_source(source)

    tasks, hidden_count = list_tasks(settings.vault_db_path, source=resolved_source)

    return {
        "metadata": _build_tasks_metadata(
            settings, resolved_source, len(tasks), hidden_count
        ),
        "tasks": tasks,
    }


@app.get("/tasks/hidden")
def get_hidden_tasks(source: str = Query(DEFAULT_SOURCE)) -> dict[str, Any]:
    settings = _get_settings()
    resolved_source = _resolve_source(source)
    hidden_items = list_hidden_items(settings.vault_db_path, source=resolved_source)

    return {
        "tasks": [
            {
                "id": row["item_key"],
                "title": row["title"],
                "class_name": row["subject_name"],
                "description": "",
                "due_date": None,
                "hidden_at": row["hidden_at"],
            }
            for row in hidden_items
        ]
    }


@app.post("/tasks/hide")
def hide_assignment(payload: HideTaskRequest) -> dict[str, Any]:
    task_id = payload.task_id.strip()
    task_title = payload.task_title.strip()
    class_name = payload.class_name.strip()
    if not task_id:
        raise HTTPException(status_code=400, detail="task_id is required.")
    if not task_title:
        raise HTTPException(status_code=400, detail="task_title is required.")
    if not class_name:
        raise HTTPException(status_code=400, detail="class_name is required.")

    settings = _get_settings()
    hide_task(
        settings.vault_db_path,
        task_id=task_id,
        task_title=task_title,
        class_name=class_name,
        hidden_at=datetime.now(timezone.utc).isoformat(),
    )
    return {
        "success": True,
        "message": "Task hidden.",
        "task_id": task_id,
    }


@app.post("/tasks/recover")
def recover_assignment(payload: TaskMutationRequest) -> dict[str, Any]:
    task_id = payload.task_id.strip()
    if not task_id:
        raise HTTPException(status_code=400, detail="task_id is required.")

    settings = _get_settings()
    recovered = recover_task(settings.vault_db_path, task_id)
    if not recovered:
        raise HTTPException(status_code=404, detail="Task is not hidden.")

    return {
        "success": True,
        "message": "Task recovered.",
        "task_id": task_id,
    }


@app.delete("/tasks/permanent")
def permanently_delete_assignment(payload: TaskMutationRequest) -> dict[str, Any]:
    task_id = payload.task_id.strip()
    if not task_id:
        raise HTTPException(status_code=400, detail="task_id is required.")

    settings = _get_settings()
    deleted = permanently_delete_task(settings.vault_db_path, task_id)
    if not deleted:
        raise HTTPException(status_code=404, detail="Task is not in completed list.")

    return {
        "success": True,
        "message": "Task permanently deleted.",
        "task_id": task_id,
    }


@app.get("/subjects")
def get_subjects(source: str | None = Query(None)) -> dict[str, Any]:
    settings = _get_settings()
    resolved_source = _resolve_source(source) if source else None
    return {"subjects": list_subjects(settings.vault_db_path, source=resolved_source)}


@app.get("/sync/status")
def get_sync_status() -> dict[str, Any]:
    """Per-platform sync state.

    Kognity has no ingestion worker yet, so it reports not_configured rather
    than being absent — the UI can render both platforms from one shape.
    """
    settings = _get_settings()

    statuses = []
    for source in KNOWN_SOURCES:
        last_run = get_last_sync_run(settings.vault_db_path, source=source)
        if last_run is None:
            statuses.append(
                {
                    "source": source,
                    "status": _never_run_status(source),
                    "last_run_at": None,
                    "total_items": 0,
                    "parse_errors": 0,
                    "message": None,
                }
            )
            continue

        statuses.append(
            {
                "source": source,
                "status": last_run["status"],
                "last_run_at": last_run["finished_at"] or last_run["started_at"],
                "total_items": last_run["total_items"],
                "parse_errors": last_run["parse_errors"],
                "message": last_run["message"],
            }
        )

    return {"sources": statuses}


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
