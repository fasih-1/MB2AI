"""Assessment-criteria extraction.

The expected values here come from a real task brief in this repo, which writes
"Criterion B: Investigating" and "Criterion C: Communicating".
"""

from __future__ import annotations

import json
import logging
from pathlib import Path

import pytest

from src import api, vault
from src.rubric import extract_criteria, merge_criteria

from tests.conftest import make_settings, make_task

LOG = logging.getLogger("test")


def letters(criteria) -> list[str]:
    return [c["letter"] for c in criteria]


class TestNamedCriteria:
    def test_matches_the_real_brief_wording(self):
        text = (
            "This task is assessed against Criterion B: Investigating and "
            "Criterion C: Communicating."
        )
        assert extract_criteria(text) == [
            {"letter": "B", "name": "Investigating"},
            {"letter": "C", "name": "Communicating"},
        ]

    def test_captures_a_multi_word_name(self):
        result = extract_criteria("Criterion A: Knowing and understanding")
        assert result == [{"letter": "A", "name": "Knowing and understanding"}]

    def test_strips_trailing_punctuation(self):
        result = extract_criteria("assessed against Criterion D: Reflecting.")
        assert result == [{"letter": "D", "name": "Reflecting"}]

    def test_handles_an_en_dash_separator(self):
        result = extract_criteria("Criterion B – Investigating")
        assert result == [{"letter": "B", "name": "Investigating"}]


class TestBareCriteria:
    @pytest.mark.parametrize(
        "text,expected",
        [
            ("Criteria A and B", ["A", "B"]),
            ("Criteria: A, C", ["A", "C"]),
            ("Criterion A, B & C", ["A", "B", "C"]),
            ("Criteria B + C", ["B", "C"]),
        ],
    )
    def test_letters_without_names(self, text, expected):
        result = extract_criteria(text)
        assert letters(result) == expected
        assert all(c["name"] is None for c in result)


class TestRejection:
    @pytest.mark.parametrize(
        "text",
        [
            "",
            None,
            "no criteria here",
            "the criteria for success are unclear",
            "Criterion E: Nonexistent",
            "Section A of the report",
        ],
    )
    def test_finds_nothing(self, text):
        assert extract_criteria(text) == []

    def test_ignores_letters_beyond_d(self):
        """MYP runs A-D; anything past that is far more likely a false hit."""
        assert letters(extract_criteria("Criterion F: Made Up")) == []


class TestOrderingAndMerging:
    def test_always_ordered_a_to_d(self):
        text = "Criterion D: Reflecting, then Criterion A: Knowing"
        assert letters(extract_criteria(text)) == ["A", "D"]

    def test_deduplicates_repeats(self):
        text = "Criterion B: Investigating ... again Criterion B: Investigating"
        assert letters(extract_criteria(text)) == ["B"]

    def test_a_name_wins_over_a_bare_mention(self):
        result = extract_criteria("Criteria A and B", "Criterion B: Investigating")
        assert result == [
            {"letter": "A", "name": None},
            {"letter": "B", "name": "Investigating"},
        ]

    def test_order_of_sources_does_not_matter(self):
        a = extract_criteria("Criteria A and B", "Criterion B: Investigating")
        b = extract_criteria("Criterion B: Investigating", "Criteria A and B")
        assert a == b

    def test_merge_prefers_a_name(self):
        merged = merge_criteria(
            [{"letter": "B", "name": None}],
            [{"letter": "B", "name": "Investigating"}],
        )
        assert merged == [{"letter": "B", "name": "Investigating"}]

    def test_merge_tolerates_junk(self):
        merged = merge_criteria(
            [{"letter": "B", "name": "Investigating"}],
            ["garbage", None, {"letter": "Z"}, {}],
        )
        assert merged == [{"letter": "B", "name": "Investigating"}]

    def test_merge_handles_empty_inputs(self):
        assert merge_criteria(None, None) == []


class TestIngestion:
    def test_populates_criteria_from_the_task_description(self, vault_path: Path):
        vault.ingest_scrape_payload(
            vault_path,
            {"tasks": [make_task(
                "Summative", "Design",
                full_description="Assessed against Criterion B: Investigating.",
            )]},
        )
        task = vault.list_tasks(vault_path)[0][0]
        assert task["rubric_criteria"] == [
            {"letter": "B", "name": "Investigating"}
        ]

    def test_defaults_to_empty_when_none_are_mentioned(self, seeded_vault: Path):
        for task in vault.list_tasks(seeded_vault)[0]:
            assert task["rubric_criteria"] == []

    def test_rescrape_without_criteria_does_not_wipe_them(self, vault_path: Path):
        """Criteria recovered from an attachment must survive a plain re-scrape."""
        payload = {"tasks": [make_task(
            "Summative", "Design", full_description="See attached brief.",
        )]}
        vault.ingest_scrape_payload(vault_path, payload)

        task = vault.find_task_by_title(vault_path, "Design", "Summative")
        vault.update_task_rubric_criteria(
            vault_path, int(task["id"]), [{"letter": "B", "name": "Investigating"}]
        )

        vault.ingest_scrape_payload(vault_path, payload)

        refreshed = vault.find_task_by_title(vault_path, "Design", "Summative")
        assert json.loads(refreshed["rubric_criteria"]) == [
            {"letter": "B", "name": "Investigating"}
        ]


class TestUpdateTaskRubricCriteria:
    def test_merges_into_existing(self, vault_path: Path):
        vault.ingest_scrape_payload(
            vault_path,
            {"tasks": [make_task(
                "Summative", "Design", full_description="Criteria A and B",
            )]},
        )
        task = vault.find_task_by_title(vault_path, "Design", "Summative")

        stored = vault.update_task_rubric_criteria(
            vault_path, int(task["id"]), [{"letter": "B", "name": "Investigating"}]
        )
        assert stored == [
            {"letter": "A", "name": None},
            {"letter": "B", "name": "Investigating"},
        ]

    def test_unknown_task_returns_empty(self, vault_path: Path):
        vault._ensure_db(vault_path)
        assert vault.update_task_rubric_criteria(vault_path, 9999, []) == []


class TestAttachmentEnrichment:
    def test_criteria_are_recovered_from_an_attached_brief(
        self, tmp_path: Path, vault_path: Path
    ):
        """The real summative brief names criteria only inside the attachment."""
        brief = tmp_path / "data/attachments/hw/brief.txt"
        brief.parent.mkdir(parents=True, exist_ok=True)
        brief.write_text(
            "Assessed against Criterion B: Investigating and "
            "Criterion C: Communicating.",
            encoding="utf-8",
        )

        vault.ingest_scrape_payload(
            vault_path,
            {"tasks": [make_task(
                "Summative", "Design",
                full_description="See the attached brief.",
                attachments=[str(brief)],
            )]},
            project_root=tmp_path,
        )

        task = vault.find_task_by_title(vault_path, "Design", "Summative")
        assert json.loads(task["rubric_criteria"]) == []

        settings = make_settings(tmp_path, vault_path)
        api._scraped_attachment_context(settings, "Design", "Summative", LOG)

        refreshed = vault.find_task_by_title(vault_path, "Design", "Summative")
        assert json.loads(refreshed["rubric_criteria"]) == [
            {"letter": "B", "name": "Investigating"},
            {"letter": "C", "name": "Communicating"},
        ]

    def test_attachment_without_criteria_leaves_the_task_alone(
        self, tmp_path: Path, vault_path: Path
    ):
        brief = tmp_path / "data/attachments/hw/brief.txt"
        brief.parent.mkdir(parents=True, exist_ok=True)
        brief.write_text("Just do the reading.", encoding="utf-8")

        vault.ingest_scrape_payload(
            vault_path,
            {"tasks": [make_task("Homework", "Maths", attachments=[str(brief)])]},
            project_root=tmp_path,
        )
        settings = make_settings(tmp_path, vault_path)
        api._scraped_attachment_context(settings, "Maths", "Homework", LOG)

        task = vault.find_task_by_title(vault_path, "Maths", "Homework")
        assert json.loads(task["rubric_criteria"]) == []
