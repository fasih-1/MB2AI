from __future__ import annotations

import re
import time
import math
from datetime import datetime, timezone
from pathlib import Path
from typing import Any

from .providers import GenerationRequest, LLMProvider, ProviderRouter
from .vault import save_draft


SYSTEM_INSTRUCTION = (
    "You are an elite IB MYP 5 Study Assistant. Your job is NOT to write the "
    "assignment for the student. Act as a brilliant tutor who breaks down "
    "complex tasks into manageable action plans. Read the assignment instructions "
    "and provide: 1. Task Translation (What the teacher actually wants in 2 "
    "sentences). 2. Step-by-Step Action Plan (A checklist to complete the task). "
    "3. Research/Brainstorming Guide (Key concepts to review, outlines, or debate "
    "prep). Do not use overly formal AI words like \"delve\" or \"tapestry\". "
    "Keep the tone practical and structured."
)

GHOSTWRITER_SYSTEM_INSTRUCTION = (
    "Act as an expert student. Your job is to draft the actual final assignment, "
    "essay, or debate points exactly as requested by the rubric. Write the complete "
    "draft ready for manual review."
)

SUPPORTED_MODES = {"tutor", "ghostwriter"}

# Fallback description budget. The real limit comes from the routed provider's
# max_description_chars, so a large-context backend is not capped to Groq's.
MAX_DESCRIPTION_CHARS = 1500
TRUNCATION_SUFFIX = "... [TRUNCATED FOR LENGTH]"


def _sanitize_name(value: str) -> str:
    cleaned = re.sub(r"[<>:\"/\\|?*]+", "_", (value or "").strip())
    cleaned = re.sub(r"\s+", " ", cleaned).strip().strip(".")
    return cleaned[:120] or "untitled"


def _build_prompt(
    task: dict[str, Any],
    custom_instructions: str | None = "",
    source_document_context: str | None = "",
) -> str:
    prompt = (
        "Generate a study-assistant response in Markdown using the required structure.\n\n"
        f"Title: {task.get('title', '')}\n"
        f"Class: {task.get('class_name', '')}\n"
        f"Due Date: {task.get('due_date', '')}\n\n"
        "Assignment Instructions:\n"
        f"{task.get('full_description', '')}\n"
    )

    instructions = (custom_instructions or "").strip()
    if instructions:
        prompt += f"\nAdditional User Instructions:\n{instructions}\n"

    source_context = (source_document_context or "").strip()
    if source_context:
        prompt += f"\nSource Document Context:\n{source_context}\n"

    return prompt


def _apply_description_failsafe(
    description: str, max_chars: int = MAX_DESCRIPTION_CHARS
) -> tuple[str, bool, int]:
    original_len = len(description)
    if original_len <= max_chars:
        return description, False, original_len

    truncated = description[:max_chars] + TRUNCATION_SUFFIX
    return truncated, True, original_len


def _resolve_mode(mode: str | None) -> str:
    normalized = (mode or "tutor").strip().lower()
    if normalized in SUPPORTED_MODES:
        return normalized
    return "tutor"


def _system_instruction_for_mode(mode: str) -> str:
    if mode == "ghostwriter":
        return GHOSTWRITER_SYSTEM_INSTRUCTION
    return SYSTEM_INSTRUCTION


def _notify_draft_ready(title: str, class_name: str, logger) -> None:
    message = f"Draft Ready: {title} ({class_name})"
    logger.info("NOTIFY_BACKEND_SUPPRESSED message=%s", message)


def _write_markdown(output_path: Path, body: str) -> None:
    output_path.parent.mkdir(parents=True, exist_ok=True)
    output_path.write_text(body.strip() + "\n", encoding="utf-8")


def generate_drafts_from_tasks(
    tasks: list[dict[str, Any]],
    output_base: Path,
    provider_router: ProviderRouter,
    logger,
    mode: str = "tutor",
    class_name: str | None = None,
    task_title: str | None = None,
    custom_instructions: str | None = "",
    source_document_context: str | None = "",
    vault_db_path: Path | None = None,
) -> dict[str, int]:
    resolved_mode = _resolve_mode(mode)
    if resolved_mode != (mode or "").strip().lower():
        logger.info("GEN_MODE_FALLBACK requested=%s resolved=%s", mode, resolved_mode)

    logger.info(
        "GEN_CONFIG router=%s mode=%s",
        provider_router.describe(),
        resolved_mode,
    )

    if not isinstance(tasks, list):
        raise ValueError("Expected a list of task dicts.")

    generated = 0
    skipped = 0
    failed = 0

    normalized_class = (class_name or "").strip()
    normalized_title = (task_title or "").strip()
    has_filter = bool(normalized_class and normalized_title)
    matched_tasks = 0

    if has_filter:
        logger.info(
            "GEN_FILTER_ENABLED class=%s title=%s",
            normalized_class,
            normalized_title,
        )

    for task in tasks:
        title = str(task.get("title") or "Untitled Task")
        class_name = str(task.get("class_name") or "Unknown Class")
        full_description = str(task.get("full_description") or "").strip()

        if has_filter and (class_name != normalized_class or title != normalized_title):
            continue

        if has_filter:
            matched_tasks += 1

        if not full_description:
            skipped += 1
            logger.info("GEN_SKIP_EMPTY_DESCRIPTION title=%s class=%s", title, class_name)
            continue

        # Route on the untruncated prompt: its full size is the honest measure
        # of how much context this task actually needs.
        routing_task = dict(task)
        routing_task["full_description"] = full_description
        prompt = _build_prompt(
            routing_task,
            custom_instructions=custom_instructions,
            source_document_context=source_document_context,
        )
        provider = provider_router.select(len(prompt))

        safe_description, was_truncated, original_len = _apply_description_failsafe(
            full_description, provider.max_description_chars
        )
        if was_truncated:
            logger.info(
                "GEN_DESCRIPTION_TRUNCATED title=%s class=%s provider=%s original_len=%s kept_len=%s",
                title,
                class_name,
                provider.name,
                original_len,
                len(safe_description),
            )

            task_for_prompt = dict(task)
            task_for_prompt["full_description"] = safe_description
            prompt = _build_prompt(
                task_for_prompt,
                custom_instructions=custom_instructions,
                source_document_context=source_document_context,
            )

        logger.info(
            "GEN_ROUTE title=%s provider=%s model=%s prompt_chars=%s",
            title,
            provider.name,
            provider.model,
            len(prompt),
        )

        start = time.perf_counter()
        try:
            body = provider.generate(
                GenerationRequest(
                    system_instruction=_system_instruction_for_mode(resolved_mode),
                    prompt=prompt,
                )
            )

            class_dir = output_base / _sanitize_name(class_name)
            file_name = f"{_sanitize_name(title)}.md"
            output_path = class_dir / file_name

            _write_markdown(output_path, body)

            if vault_db_path is not None:
                try:
                    save_draft(
                        vault_path=vault_db_path,
                        task_title=title,
                        class_name=class_name,
                        mode=resolved_mode,
                        created_at=datetime.now(timezone.utc).isoformat(),
                        content=body,
                    )
                except Exception as vault_exc:
                    logger.warning(
                        "VAULT_SAVE_FAILED title=%s class=%s reason=%s",
                        title,
                        class_name,
                        vault_exc,
                    )

            generated += 1

            elapsed_ms = int((time.perf_counter() - start) * 1000)
            logger.info(
                "GEN_SUCCESS title=%s class=%s path=%s duration_ms=%s mode=%s provider=%s",
                title,
                class_name,
                output_path,
                elapsed_ms,
                resolved_mode,
                provider.name,
            )
            _notify_draft_ready(title, class_name, logger)

            # Free-tier pacing, sized to the routed provider's rate limit.
            time.sleep(provider.pacing_seconds)
        except Exception as exc:
            failed += 1
            elapsed_ms = int((time.perf_counter() - start) * 1000)
            logger.warning(
                "GEN_FAILED title=%s class=%s reason=%s duration_ms=%s mode=%s provider=%s",
                title,
                class_name,
                exc,
                elapsed_ms,
                resolved_mode,
                provider.name,
            )

    if has_filter and matched_tasks == 0:
        logger.warning(
            "GEN_FILTER_NO_MATCH class=%s title=%s",
            normalized_class,
            normalized_title,
        )

    return {"generated": generated, "skipped": skipped, "failed": failed}
