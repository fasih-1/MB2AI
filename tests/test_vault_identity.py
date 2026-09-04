"""Task identity, badge parsing, and attachment paths."""

from __future__ import annotations

from pathlib import Path

import pytest

from src import vault


class TestSourceTaskId:
    @pytest.mark.parametrize(
        "href,expected",
        [
            ("/student/classes/12846944/core_tasks/47949059", "47949059"),
            ("https://x.managebac.com/student/classes/1/core_tasks/98765", "98765"),
            ("/student/tasks/24680", "24680"),
            ("/student/assignments/13579", "13579"),
        ],
    )
    def test_prefers_the_id_in_the_url(self, href: str, expected: str):
        assert vault.derive_source_task_id(href, "Any Class", "Any Title") == expected

    @pytest.mark.parametrize("href", [None, "", "   ", "/student/classes/12846944"])
    def test_falls_back_to_a_content_hash(self, href):
        result = vault.derive_source_task_id(href, "Maths", "Homework 1")
        assert result == vault.alias_key_for("Maths", "Homework 1")
        assert result.startswith("h:")

    def test_is_independent_of_list_position(self):
        """The original scheme hashed in the row's index, so every id changed
        when ManageBac re-ordered the dashboard. That is the bug this fixes."""
        first = vault.derive_source_task_id(None, "Maths", "Homework 1")
        again = vault.derive_source_task_id(None, "Maths", "Homework 1")
        assert first == again

    def test_distinguishes_different_tasks(self):
        a = vault.derive_source_task_id(None, "Maths", "Homework 1")
        b = vault.derive_source_task_id(None, "Maths", "Homework 2")
        assert a != b

    def test_ignores_whitespace_and_case(self):
        assert vault.derive_source_task_id(None, "Maths", "Homework 1") == (
            vault.derive_source_task_id(None, "  maths ", "homework   1")
        )


class TestSubjectId:
    def test_extracts_class_id(self):
        href = "/student/classes/12846944/core_tasks/47949059"
        assert vault.derive_source_subject_id(href) == "12846944"

    @pytest.mark.parametrize("href", [None, "", "/student/core_tasks/47949059"])
    def test_returns_none_without_a_class_segment(self, href):
        assert vault.derive_source_subject_id(href) is None


class TestBadgeParsing:
    def test_parses_a_full_badge_string(self):
        parsed = vault._parse_badges("Formative, Homework /10%, Pending")
        assert parsed == {
            "task_type": "Formative",
            "category": "Homework",
            "weight": "10%",
            "status": "Pending",
        }

    def test_parses_summative(self):
        parsed = vault._parse_badges("Summative, Project /25%, Submitted")
        assert parsed["task_type"] == "Summative"
        assert parsed["category"] == "Project"
        assert parsed["weight"] == "25%"
        assert parsed["status"] == "Submitted"

    @pytest.mark.parametrize("value", [None, "", "   ", ",,,"])
    def test_empty_input_yields_all_none(self, value):
        assert set(vault._parse_badges(value).values()) == {None}

    def test_unknown_tokens_do_not_crash(self):
        parsed = vault._parse_badges("Something Unexpected")
        assert parsed["category"] == "Something Unexpected"
        assert parsed["task_type"] is None

    def test_parse_is_never_lossy_because_summary_is_kept_raw(
        self, vault_path: Path
    ):
        from tests.conftest import make_task

        raw = "Weird, Unparseable, Badge, Soup"
        vault.ingest_scrape_payload(
            vault_path,
            {"tasks": [make_task("T", "C", description=raw)]},
        )
        task = vault.list_tasks(vault_path)[0][0]
        assert task["description"] == raw


class TestAttachmentPaths:
    def test_relativizes_paths_under_the_project(self, tmp_path: Path):
        target = tmp_path / "data" / "attachments" / "task" / "file.pdf"
        target.parent.mkdir(parents=True)
        target.write_text("x", encoding="utf-8")

        result = vault._relative_attachment_path(str(target), tmp_path)
        assert result == "data/attachments/task/file.pdf"

    def test_recovers_the_tail_of_a_stale_absolute_path(self):
        """Paths recorded before the project moved on disk still resolve to a
        usable project-relative path."""
        stale = r"C:\Users\Someone\Desktop\MB2AI\data\attachments\hw\file.pdf"
        result = vault._relative_attachment_path(stale, None)
        assert result == "data/attachments/hw/file.pdf"

    def test_leaves_unrecognisable_paths_alone(self):
        result = vault._relative_attachment_path("/elsewhere/file.pdf", None)
        assert result.endswith("file.pdf")

    def test_ingest_stores_relative_paths(self, vault_path: Path, tmp_path: Path):
        from tests.conftest import make_task

        absolute = tmp_path / "data" / "attachments" / "hw" / "brief.pdf"
        absolute.parent.mkdir(parents=True)
        absolute.write_text("x", encoding="utf-8")

        vault.ingest_scrape_payload(
            vault_path,
            {"tasks": [make_task("T", "C", attachments=[str(absolute)])]},
            project_root=tmp_path,
        )

        task = vault.list_tasks(vault_path)[0][0]
        assert task["local_attachments"] == ["data/attachments/hw/brief.pdf"]
