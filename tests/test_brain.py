"""Generation orchestration.

brain.py's prompt text and the tutor/ghostwriter split are deliberately fixed,
so these tests pin the behaviour around them: routing, per-provider truncation,
filtering, and what gets written where.
"""

from __future__ import annotations

import logging
from pathlib import Path

import pytest

from src import providers as P, vault
from src.brain import (
    MAX_DESCRIPTION_CHARS,
    TRUNCATION_SUFFIX,
    generate_drafts_from_tasks,
)

from tests.conftest import make_task

LOG = logging.getLogger("test")


class RecordingProvider(P.LLMProvider):
    """Captures each prompt instead of calling a backend."""

    def __init__(self, name="groq", max_description_chars=1500):
        super().__init__("key", f"{name}-model", LOG)
        self.name = name
        self.max_description_chars = max_description_chars
        self.pacing_seconds = 0
        self.prompts: list[str] = []
        self.system_instructions: list[str] = []

    def _complete(self, request: P.GenerationRequest) -> str:
        self.prompts.append(request.prompt)
        self.system_instructions.append(request.system_instruction)
        return f"# draft from {self.name}"

    def description_sent(self, index: int = 0) -> str:
        body = self.prompts[index].split("Assignment Instructions:\n", 1)[1]
        return body.rstrip("\n")


def router_for(**providers) -> P.ProviderRouter:
    return P.ProviderRouter(providers, LOG, threshold_chars=12000)


def run(tasks, output, router, **kwargs):
    return generate_drafts_from_tasks(
        tasks=tasks, output_base=output, provider_router=router, logger=LOG, **kwargs
    )


class TestOutputs:
    def test_writes_a_markdown_file_per_task(self, tmp_path: Path):
        groq = RecordingProvider()
        summary = run(
            [make_task("Homework 1", "IB MYP Maths (Grade 10)")],
            tmp_path, router_for(groq=groq),
        )
        assert summary == {"generated": 1, "skipped": 0, "failed": 0}
        assert (tmp_path / "IB MYP Maths (Grade 10)" / "Homework 1.md").exists()

    def test_sanitizes_names_for_the_filesystem(self, tmp_path: Path):
        run(
            [make_task("A/B:C?", "Class<>|Name")],
            tmp_path, router_for(groq=RecordingProvider()),
        )
        written = list(tmp_path.rglob("*.md"))
        assert len(written) == 1
        assert "/" not in written[0].name

    def test_saves_to_the_vault_when_given_a_path(self, tmp_path: Path):
        db = tmp_path / "vault.db"
        run(
            [make_task("Homework 1", "Maths")],
            tmp_path, router_for(groq=RecordingProvider()), vault_db_path=db,
        )
        drafts = vault.list_drafts(db)
        assert len(drafts) == 1 and drafts[0]["task_title"] == "Homework 1"

    def test_skips_tasks_with_no_description(self, tmp_path: Path):
        summary = run(
            [make_task("Empty", "Maths", full_description="   ")],
            tmp_path, router_for(groq=RecordingProvider()),
        )
        assert summary == {"generated": 0, "skipped": 1, "failed": 0}

    def test_counts_a_failing_provider(self, tmp_path: Path):
        class Failing(RecordingProvider):
            def _complete(self, request):
                raise ValueError("backend exploded")

        summary = run(
            [make_task("Homework 1", "Maths")],
            tmp_path, router_for(groq=Failing()),
        )
        assert summary["failed"] == 1

    def test_rejects_a_non_list(self, tmp_path: Path):
        with pytest.raises(ValueError):
            run("not a list", tmp_path, router_for(groq=RecordingProvider()))


class TestModes:
    def test_tutor_is_the_default_instruction(self, tmp_path: Path):
        groq = RecordingProvider()
        run([make_task("T", "C")], tmp_path, router_for(groq=groq))
        assert "NOT to write the assignment" in groq.system_instructions[0]

    def test_ghostwriter_uses_its_own_instruction(self, tmp_path: Path):
        groq = RecordingProvider()
        run([make_task("T", "C")], tmp_path, router_for(groq=groq), mode="ghostwriter")
        assert "draft the actual final assignment" in groq.system_instructions[0]

    def test_unknown_mode_falls_back_to_tutor(self, tmp_path: Path):
        groq = RecordingProvider()
        run([make_task("T", "C")], tmp_path, router_for(groq=groq), mode="nonsense")
        assert "NOT to write the assignment" in groq.system_instructions[0]

    def test_mode_is_recorded_on_the_draft(self, tmp_path: Path):
        db = tmp_path / "vault.db"
        run(
            [make_task("T", "C")], tmp_path, router_for(groq=RecordingProvider()),
            mode="ghostwriter", vault_db_path=db,
        )
        assert vault.list_drafts(db)[0]["mode"] == "ghostwriter"


class TestFiltering:
    def test_generates_only_the_named_task(self, tmp_path: Path):
        groq = RecordingProvider()
        tasks = [
            make_task("Homework 1", "Maths"),
            make_task("Homework 2", "Maths"),
            make_task("Homework 1", "Physics"),
        ]
        summary = run(
            tasks, tmp_path, router_for(groq=groq),
            class_name="Maths", task_title="Homework 2",
        )
        assert summary["generated"] == 1
        assert "Homework 2" in groq.prompts[0]

    def test_no_match_generates_nothing(self, tmp_path: Path):
        summary = run(
            [make_task("Homework 1", "Maths")], tmp_path,
            router_for(groq=RecordingProvider()),
            class_name="Maths", task_title="Nonexistent",
        )
        assert summary["generated"] == 0

    def test_a_partial_filter_is_ignored(self, tmp_path: Path):
        """Both halves are required; a class alone must not silently filter."""
        summary = run(
            [make_task("A", "Maths"), make_task("B", "Physics")],
            tmp_path, router_for(groq=RecordingProvider()), class_name="Maths",
        )
        assert summary["generated"] == 2


class TestRoutingAndTruncation:
    def test_small_task_goes_to_groq(self, tmp_path: Path):
        groq, gemini = RecordingProvider("groq"), RecordingProvider("gemini", 60000)
        run([make_task("T", "C")], tmp_path, router_for(groq=groq, gemini=gemini))
        assert len(groq.prompts) == 1 and not gemini.prompts

    def test_large_task_goes_to_gemini(self, tmp_path: Path):
        groq, gemini = RecordingProvider("groq"), RecordingProvider("gemini", 60000)
        run(
            [make_task("T", "C", full_description="CONTEXT " * 4000)],
            tmp_path, router_for(groq=groq, gemini=gemini),
        )
        assert len(gemini.prompts) == 1 and not groq.prompts

    def test_groq_truncation_is_unchanged(self, tmp_path: Path):
        """The pre-abstraction behaviour must be preserved exactly."""
        groq = RecordingProvider("groq", max_description_chars=1500)
        run(
            [make_task("T", "C", full_description="X" * 32000)],
            tmp_path, router_for(groq=groq),
        )
        sent = groq.description_sent()
        assert sent.endswith(TRUNCATION_SUFFIX)
        assert len(sent) == MAX_DESCRIPTION_CHARS + len(TRUNCATION_SUFFIX)

    def test_gemini_receives_the_untruncated_description(self, tmp_path: Path):
        """The point of the large-context backend: no needless chopping."""
        groq, gemini = RecordingProvider("groq"), RecordingProvider("gemini", 60000)
        description = "CONTEXT " * 4000
        run(
            [make_task("T", "C", full_description=description)],
            tmp_path, router_for(groq=groq, gemini=gemini),
        )
        sent = gemini.description_sent()
        assert TRUNCATION_SUFFIX not in sent
        assert len(sent) >= len(description.strip())

    def test_routing_measures_the_untruncated_prompt(self, tmp_path: Path):
        """Routing on the post-truncation size would pin everything to Groq,
        since truncation is what makes it fit in the first place."""
        groq, gemini = RecordingProvider("groq"), RecordingProvider("gemini", 60000)
        run(
            [make_task("T", "C", full_description="Y" * 20000)],
            tmp_path, router_for(groq=groq, gemini=gemini),
        )
        assert len(gemini.prompts) == 1

    def test_prompt_carries_the_task_context(self, tmp_path: Path):
        groq = RecordingProvider()
        run(
            [make_task("Homework 1", "IB MYP Maths (Grade 10)")],
            tmp_path, router_for(groq=groq),
        )
        prompt = groq.prompts[0]
        assert "Homework 1" in prompt
        assert "IB MYP Maths (Grade 10)" in prompt

    def test_custom_instructions_and_source_context_reach_the_prompt(
        self, tmp_path: Path
    ):
        groq = RecordingProvider()
        run(
            [make_task("T", "C")], tmp_path, router_for(groq=groq),
            custom_instructions="Focus on criterion B.",
            source_document_context="Extracted PDF text here.",
        )
        prompt = groq.prompts[0]
        assert "Focus on criterion B." in prompt
        assert "Extracted PDF text here." in prompt
