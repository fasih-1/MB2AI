from __future__ import annotations

from io import BytesIO

from fastapi import HTTPException
from PyPDF2 import PdfReader

ALLOWED_EXTENSIONS = {".txt", ".md", ".pdf"}
MAX_UPLOAD_BYTES = 10 * 1024 * 1024


def extract_text_from_attachment(filename: str, data: bytes) -> str:
    if not filename:
        raise HTTPException(status_code=400, detail="Attachment filename is required.")

    if len(data) > MAX_UPLOAD_BYTES:
        raise HTTPException(status_code=413, detail="Attachment exceeds 10MB limit.")

    lower = filename.lower()
    extension = "." + lower.rsplit(".", 1)[-1] if "." in lower else ""
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