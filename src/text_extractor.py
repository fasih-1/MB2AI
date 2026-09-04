from __future__ import annotations

from io import BytesIO
from pathlib import Path

from fastapi import HTTPException
from PyPDF2 import PdfReader

ALLOWED_EXTENSIONS = {".txt", ".md", ".pdf"}
MAX_UPLOAD_BYTES = 10 * 1024 * 1024


def _extension(filename: str) -> str:
    lower = (filename or "").lower()
    return "." + lower.rsplit(".", 1)[-1] if "." in lower else ""


def extract_text_from_path(path: Path) -> str:
    """Best-effort extraction from a file already on disk.

    Unlike extract_text_from_attachment, which validates a user upload and
    raises, this returns "" for anything it cannot read. Scraped attachments
    include types the extractor does not handle (.docx, .jpeg) and files whose
    recorded path may be stale, and neither should fail a generation run.
    """
    try:
        if not path.is_file():
            return ""
        if _extension(path.name) not in ALLOWED_EXTENSIONS:
            return ""
        if path.stat().st_size > MAX_UPLOAD_BYTES:
            return ""
        return extract_text_from_attachment(path.name, path.read_bytes())
    except Exception:
        return ""


def extract_text_from_attachment(filename: str, data: bytes) -> str:
    if not filename:
        raise HTTPException(status_code=400, detail="Attachment filename is required.")

    if len(data) > MAX_UPLOAD_BYTES:
        raise HTTPException(status_code=413, detail="Attachment exceeds 10MB limit.")

    extension = _extension(filename)
    if extension not in ALLOWED_EXTENSIONS:
        raise HTTPException(status_code=400, detail="Unsupported attachment type.")

    if extension in {".txt", ".md"}:
        return data.decode("utf-8", errors="ignore").strip()

    reader = PdfReader(BytesIO(data))
    pages: list[str] = []
    for page in reader.pages:
        text = page.extract_text() or ""
        text = text.strip()
        if text:
            pages.append(text)

    return "\n\n".join(pages).strip()