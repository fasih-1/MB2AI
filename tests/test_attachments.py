"""Feeding scraped attachments into generation.

The scraper downloads assignment attachments and records them, but generation
used to ignore them and make the user re-upload the same file by hand.
"""

from __future__ import annotations

import logging
from pathlib import Path

from src import api, vault
from src.text_extractor import extract_text_from_path

from tests.conftest import make_settings, make_task

LOG = logging.getLogger("test")


def seed_task_with_attachment(
    vault_path: Path, project_root: Path, filename: str, body: str | None = "brief text"
) -> Path:
    """Create a task whose attachment exists on disk under project_root."""
    relative = Path("data/attachments/hw") / filename
    absolute = project_root / relative
    absolute.parent.mkdir(parents=True, exist_ok=True)
    if body is not None:
        absolute.write_text(body, encoding="utf-8")

    vault.ingest_scrape_payload(
        vault_path,
        {"tasks": [make_task("Homework 1", "Maths", attachments=[str(absolute)])]},
        project_root=project_root,
    )
    return absolute


class TestExtractFromPath:
    def test_reads_a_text_file(self, tmp_path: Path):
        path = tmp_path / "brief.txt"
        path.write_text("the assignment brief", encoding="utf-8")
        assert extract_text_from_path(path) == "the assignment brief"

    def test_reads_markdown(self, tmp_path: Path):
        path = tmp_path / "brief.md"
        path.write_text("# Heading\n\nbody", encoding="utf-8")
        assert "Heading" in extract_text_from_path(path)

    def test_unsupported_type_returns_empty_rather_than_raising(self, tmp_path: Path):
        """The scraper also grabs .docx and images; one must not fail a run."""
        path = tmp_path / "case_study.jpeg"
        path.write_bytes(b"\xff\xd8\xff\xe0not-really-a-jpeg")
        assert extract_text_from_path(path) == ""

    def test_docx_returns_empty(self, tmp_path: Path):
        path = tmp_path / "task.docx"
        path.write_bytes(b"PK\x03\x04")
        assert extract_text_from_path(path) == ""

    def test_missing_file_returns_empty(self, tmp_path: Path):
        assert extract_text_from_path(tmp_path / "gone.pdf") == ""

    def test_oversized_file_returns_empty(self, tmp_path: Path):
        path = tmp_path / "huge.txt"
        path.write_bytes(b"x" * (10 * 1024 * 1024 + 1))
        assert extract_text_from_path(path) == ""

    def test_corrupt_pdf_returns_empty(self, tmp_path: Path):
        path = tmp_path / "broken.pdf"
        path.write_bytes(b"not a pdf at all")
        assert extract_text_from_path(path) == ""


class TestScrapedAttachmentContext:
    def test_returns_text_from_the_attachment(self, tmp_path: Path, vault_path: Path):
        seed_task_with_attachment(vault_path, tmp_path, "brief.txt", "read this")
        settings = make_settings(tmp_path, vault_path)

        context = api._scraped_attachment_context(settings, "Maths", "Homework 1", LOG)
        assert "read this" in context

    def test_names_the_source_file(self, tmp_path: Path, vault_path: Path):
        seed_task_with_attachment(vault_path, tmp_path, "brief.txt")
        settings = make_settings(tmp_path, vault_path)

        context = api._scraped_attachment_context(settings, "Maths", "Homework 1", LOG)
        assert context.startswith("--- brief.txt ---")

    def test_caches_extracted_text_on_the_row(self, tmp_path: Path, vault_path: Path):
        seed_task_with_attachment(vault_path, tmp_path, "brief.txt", "read this")
        settings = make_settings(tmp_path, vault_path)

        api._scraped_attachment_context(settings, "Maths", "Homework 1", LOG)

        task = vault.find_task_by_title(vault_path, "Maths", "Homework 1")
        rows = vault.list_task_attachments(vault_path, int(task["id"]))
        assert rows[0]["extracted_text"] == "read this"

    def test_second_call_uses_the_cache(self, tmp_path: Path, vault_path: Path):
        """A PDF should be parsed once, not on every generation."""
        absolute = seed_task_with_attachment(
            vault_path, tmp_path, "brief.txt", "original text"
        )
        settings = make_settings(tmp_path, vault_path)
        api._scraped_attachment_context(settings, "Maths", "Homework 1", LOG)

        # Deleting the file proves the second read came from the cache.
        absolute.unlink()
        context = api._scraped_attachment_context(settings, "Maths", "Homework 1", LOG)
        assert "original text" in context

    def test_combines_multiple_attachments(self, tmp_path: Path, vault_path: Path):
        first = tmp_path / "data/attachments/hw/one.txt"
        second = tmp_path / "data/attachments/hw/two.txt"
        first.parent.mkdir(parents=True, exist_ok=True)
        first.write_text("first file", encoding="utf-8")
        second.write_text("second file", encoding="utf-8")

        vault.ingest_scrape_payload(
            vault_path,
            {"tasks": [make_task(
                "Homework 1", "Maths", attachments=[str(first), str(second)]
            )]},
            project_root=tmp_path,
        )
        settings = make_settings(tmp_path, vault_path)

        context = api._scraped_attachment_context(settings, "Maths", "Homework 1", LOG)
        assert "first file" in context and "second file" in context

    def test_skips_unreadable_attachments(self, tmp_path: Path, vault_path: Path):
        readable = tmp_path / "data/attachments/hw/good.txt"
        image = tmp_path / "data/attachments/hw/photo.jpeg"
        readable.parent.mkdir(parents=True, exist_ok=True)
        readable.write_text("useful", encoding="utf-8")
        image.write_bytes(b"\xff\xd8\xff")

        vault.ingest_scrape_payload(
            vault_path,
            {"tasks": [make_task(
                "Homework 1", "Maths", attachments=[str(image), str(readable)]
            )]},
            project_root=tmp_path,
        )
        settings = make_settings(tmp_path, vault_path)

        context = api._scraped_attachment_context(settings, "Maths", "Homework 1", LOG)
        assert "useful" in context
        assert "photo.jpeg" not in context

    def test_missing_file_on_disk_yields_empty(self, tmp_path: Path, vault_path: Path):
        seed_task_with_attachment(vault_path, tmp_path, "brief.txt", body=None)
        settings = make_settings(tmp_path, vault_path)
        assert api._scraped_attachment_context(
            settings, "Maths", "Homework 1", LOG
        ) == ""

    def test_task_with_no_attachments(self, tmp_path: Path, seeded_vault: Path):
        settings = make_settings(tmp_path, seeded_vault)
        assert api._scraped_attachment_context(
            settings, "IB MYP I&S (Grade 10)", "Homework 1 unit-4", LOG
        ) == ""

    def test_unknown_task_yields_empty(self, tmp_path: Path, seeded_vault: Path):
        settings = make_settings(tmp_path, seeded_vault)
        assert api._scraped_attachment_context(
            settings, "Nowhere", "Nothing", LOG
        ) == ""

    def test_missing_filter_yields_empty(self, tmp_path: Path, seeded_vault: Path):
        """Generation without a class+title filter has no task to look up."""
        settings = make_settings(tmp_path, seeded_vault)
        assert api._scraped_attachment_context(settings, None, None, LOG) == ""


class TestGenerationPrecedence:
    """An explicit upload must win over the scraped attachment."""

    def _run(self, monkeypatch, tmp_path: Path, vault_path: Path, uploaded: str):
        seed_task_with_attachment(vault_path, tmp_path, "brief.txt", "SCRAPED TEXT")
        settings = make_settings(tmp_path, vault_path)
        monkeypatch.setattr(api, "load_settings", lambda: settings)
        monkeypatch.setattr(api, "setup_logger", lambda *a, **k: LOG)
        monkeypatch.setattr(api, "build_router", lambda *a, **k: object())

        captured: dict[str, str] = {}

        def fake_generate(**kwargs):
            captured["context"] = kwargs["source_document_context"]
            return {"generated": 1, "skipped": 0, "failed": 0}

        monkeypatch.setattr(api, "generate_drafts_from_tasks", fake_generate)
        api._run_generate_job(
            "tutor", "Maths", "Homework 1", "", uploaded
        )
        return captured["context"]

    def test_upload_wins(self, monkeypatch, tmp_path: Path, vault_path: Path):
        context = self._run(monkeypatch, tmp_path, vault_path, "UPLOADED TEXT")
        assert context == "UPLOADED TEXT"

    def test_falls_back_to_scraped_when_no_upload(
        self, monkeypatch, tmp_path: Path, vault_path: Path
    ):
        context = self._run(monkeypatch, tmp_path, vault_path, "")
        assert "SCRAPED TEXT" in context
