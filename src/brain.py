from __future__ import annotations

import json
import re
import time
import math
from pathlib import Path
from typing import Any

from groq import Groq


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

MAX_DESCRIPTION_CHARS = 1500
TRUNCATION_SUFFIX = "... [TRUNCATED FOR LENGTH]"


def _sanitize_name(value: str) -> str:
    cleaned = re.sub(r"[<>:\"/\\|?*]+", "_", (value or "").strip())
    cleaned = re.sub(r"\s+", " ", cleaned).strip().strip(".")
    return cleaned[:120] or "untitled"


def _extract_text(response: Any) -> str:
    choices = getattr(response, "choices", None) or []
    if not choices:
        raise ValueError("Groq returned no choices.")

    message = getattr(choices[0], "message", None)
    content = getattr(message, "content", None)

    if isinstance(content, str) and content.strip():
        return content.strip()

    raise ValueError("Groq returned an empty response.")


def _build_prompt(task: dict[str, Any]) -> str:
    return (
        "Generate a study-assistant response in Markdown using the required structure.\n\n"
        f"Title: {task.get('title', '')}\n"
        f"Class: {task.get('class_name', '')}\n"
        f"Due Date: {task.get('due_date', '')}\n\n"
        "Assignment Instructions:\n"
        f"{task.get('full_description', '')}\n"
    )


def _apply_description_failsafe(description: str) -> tuple[str, bool, int]:
    original_len = len(description)
    if original_len <= MAX_DESCRIPTION_CHARS:
        return description, False, original_len

    truncated = description[:MAX_DESCRIPTION_CHARS] + TRUNCATION_SUFFIX
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


def _is_retryable_error(exc: Exception) -> bool:
    message = str(exc).lower()
    return (
        "429" in message
        or "too many requests" in message
        or "timeout" in message
        or "timed out" in message
        or "deadline exceeded" in message
    )


def _is_auth_error(exc: Exception) -> bool:
    message = str(exc).lower()
    return "api_key_invalid" in message or "401" in message or "permission_denied" in message


def _extract_retry_delay_seconds(exc: Exception) -> int | None:
    message = str(exc).lower()

    # Examples we handle:
    # - "retry in 59 seconds"
    # - "retry in 12.5s"
    # - "retry_delay { seconds: 59 }"
    patterns = [
        r"retry\s+in\s+([0-9]+(?:\.[0-9]+)?)\s*(?:seconds|second|secs|sec|s)",
        r"retry_delay[^\d]*([0-9]+(?:\.[0-9]+)?)",
    ]

    for pattern in patterns:
        match = re.search(pattern, message)
        if not match:
            continue
        try:
            return max(1, int(math.ceil(float(match.group(1)))))
        except Exception:
            continue

    return None


def _generate_with_retry(
    client: Groq,
    model_name: str,
    prompt: str,
    system_instruction: str,
    logger,
) -> str:
    backoff_schedule = [15, 30, 60]
    max_attempts = 1 + len(backoff_schedule)

    for attempt in range(1, max_attempts + 1):
        try:
            response = client.chat.completions.create(
                model=model_name,
                messages=[
                    {"role": "system", "content": system_instruction},
                    {"role": "user", "content": prompt},
                ],
                # Keep output bounded to reduce TPM pressure on free tier.
                max_tokens=900,
            )
            return _extract_text(response)
        except Exception as exc:
            if _is_auth_error(exc):
                raise

            if _is_retryable_error(exc) and attempt < max_attempts:
                parsed_delay = _extract_retry_delay_seconds(exc)
                delay = parsed_delay if parsed_delay is not None else backoff_schedule[attempt - 1]
                logger.warning(
                    "GEN_RETRY attempt=%s/%s delay_s=%s reason=%s",
                    attempt,
                    max_attempts,
                    delay,
                    exc,
                )
                time.sleep(delay)
                continue
            raise


def generate_drafts_from_tasks(
    tasks_path: Path,
    output_base: Path,
    api_key: str,
    model_name: str,
    logger,
    mode: str = "tutor",
    class_name: str | None = None,
    task_title: str | None = None,
) -> dict[str, int]:
    if not api_key:
        raise ValueError("GROQ_API_KEY is missing. Set it in .env before using --generate.")

    resolved_mode = _resolve_mode(mode)
    if resolved_mode != (mode or "").strip().lower():
        logger.info("GEN_MODE_FALLBACK requested=%s resolved=%s", mode, resolved_mode)

    logger.info(
        "GEN_CONFIG model=%s api_key_len=%s mode=%s",
        model_name,
        len(api_key),
        resolved_mode,
    )

    if not tasks_path.exists():
        raise FileNotFoundError(f"tasks file not found: {tasks_path}")

    with tasks_path.open("r", encoding="utf-8") as handle:
        payload = json.load(handle)

    tasks = payload.get("tasks", []) if isinstance(payload, dict) else payload
    if not isinstance(tasks, list):
        raise ValueError("Invalid tasks_raw.json format: expected a list under 'tasks'.")

    client = Groq(api_key=api_key)

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

        safe_description, was_truncated, original_len = _apply_description_failsafe(full_description)
        if was_truncated:
            logger.info(
                "GEN_DESCRIPTION_TRUNCATED title=%s class=%s original_len=%s kept_len=%s",
                title,
                class_name,
                original_len,
                len(safe_description),
            )

        task_for_prompt = dict(task)
        task_for_prompt["full_description"] = safe_description
        prompt = _build_prompt(task_for_prompt)
        start = time.perf_counter()
        try:
            body = _generate_with_retry(
                client,
                model_name,
                prompt,
                _system_instruction_for_mode(resolved_mode),
                logger,
            )

            class_dir = output_base / _sanitize_name(class_name)
            file_name = f"{_sanitize_name(title)}.md"
            output_path = class_dir / file_name

            _write_markdown(output_path, body)
            generated += 1

            elapsed_ms = int((time.perf_counter() - start) * 1000)
            logger.info(
                "GEN_SUCCESS title=%s class=%s path=%s duration_ms=%s mode=%s",
                title,
                class_name,
                output_path,
                elapsed_ms,
                resolved_mode,
            )
            _notify_draft_ready(title, class_name, logger)

            # Free-tier pacing: avoid back-to-back requests.
            time.sleep(15)
        except Exception as exc:
            failed += 1
            elapsed_ms = int((time.perf_counter() - start) * 1000)
            logger.warning(
                "GEN_FAILED title=%s class=%s reason=%s duration_ms=%s mode=%s",
                title,
                class_name,
                exc,
                elapsed_ms,
                resolved_mode,
            )

    if has_filter and matched_tasks == 0:
        logger.warning(
            "GEN_FILTER_NO_MATCH class=%s title=%s",
            normalized_class,
            normalized_title,
        )

    return {"generated": generated, "skipped": skipped, "failed": failed}
