"""Ingestion, hides, recovery and permanent deletes."""

from __future__ import annotations

from pathlib import Path

from src import vault

from tests.conftest import make_task

HOMEWORK_ID = "47949059"
FORMATIVE_ID = "47980820"


def titles(path: Path) -> list[str]:
    return [t["title"] for t in vault.list_tasks(path)[0]]


class TestIngestion:
    def test_creates_subjects_and_tasks(self, seeded_vault: Path):
        assert len(vault.list_tasks(seeded_vault)[0]) == 3
        assert len(vault.list_subjects(seeded_vault)) == 3

    def test_links_subject_source_id_when_available(self, seeded_vault: Path):
        subjects = {s["name"]: s for s in vault.list_subjects(seeded_vault)}
        assert subjects["IB MYP I&S (Grade 10)"]["source_subject_id"] == "12846944"
        # No href on this one, so there is nothing to record.
        assert subjects["IB MYP Design (Grade 10)"]["source_subject_id"] is None

    def test_is_idempotent(self, vault_path: Path, payload):
        vault.ingest_scrape_payload(vault_path, payload)
        vault.ingest_scrape_payload(vault_path, payload)
        assert len(vault.list_tasks(vault_path)[0]) == 3
        assert len(vault.list_subjects(vault_path)) == 3

    def test_refreshes_changed_content(self, vault_path: Path, payload):
        vault.ingest_scrape_payload(vault_path, payload)
        payload["tasks"][0]["full_description"] = "Updated brief."
        vault.ingest_scrape_payload(vault_path, payload)

        task = vault.find_task(vault_path, HOMEWORK_ID)
        assert task["full_description"] == "Updated brief."

    def test_preserves_first_seen_at_across_rescrapes(
        self, vault_path: Path, payload
    ):
        vault.ingest_scrape_payload(vault_path, payload)
        first_seen = vault.find_task(vault_path, HOMEWORK_ID)["first_seen_at"]
        vault.ingest_scrape_payload(vault_path, payload)
        assert vault.find_task(vault_path, HOMEWORK_ID)["first_seen_at"] == first_seen

    def test_tolerates_a_malformed_payload(self, vault_path: Path):
        assert vault.ingest_scrape_payload(vault_path, {}) == {
            "subjects": 0,
            "tasks": 0,
            "attachments": 0,
        }
        assert vault.ingest_scrape_payload(vault_path, {"tasks": "nope"})["tasks"] == 0

    def test_skips_non_dict_entries(self, vault_path: Path):
        result = vault.ingest_scrape_payload(
            vault_path, {"tasks": [make_task("Good", "Class"), "garbage", None]}
        )
        assert result["tasks"] == 1

    def test_attachments_are_not_duplicated_on_rescrape(
        self, vault_path: Path, tmp_path: Path
    ):
        payload = {"tasks": [make_task("T", "C", attachments=["data/a/f.pdf"])]}
        vault.ingest_scrape_payload(vault_path, payload, project_root=tmp_path)
        vault.ingest_scrape_payload(vault_path, payload, project_root=tmp_path)
        assert vault.list_tasks(vault_path)[0][0]["local_attachments"] == [
            "data/a/f.pdf"
        ]


class TestHiding:
    def test_hidden_task_is_excluded(self, seeded_vault: Path):
        vault.hide_task(
            seeded_vault, HOMEWORK_ID, "Homework 1 unit-4",
            "IB MYP I&S (Grade 10)", "2026-09-01T00:00:00+00:00",
        )
        visible, hidden_count = vault.list_tasks(seeded_vault)
        assert "Homework 1 unit-4" not in [t["title"] for t in visible]
        assert hidden_count == 1

    def test_hide_survives_a_rescrape(self, vault_path: Path, payload):
        """The whole point of stable ids: a re-scrape must not resurrect it."""
        vault.ingest_scrape_payload(vault_path, payload)
        vault.hide_task(
            vault_path, HOMEWORK_ID, "Homework 1 unit-4",
            "IB MYP I&S (Grade 10)", "2026-09-01T00:00:00+00:00",
        )
        vault.ingest_scrape_payload(vault_path, payload)
        assert "Homework 1 unit-4" not in titles(vault_path)

    def test_hide_is_upsert_not_duplicate(self, seeded_vault: Path):
        for _ in range(3):
            vault.hide_task(
                seeded_vault, HOMEWORK_ID, "Homework 1 unit-4",
                "IB MYP I&S (Grade 10)", "2026-09-01T00:00:00+00:00",
            )
        assert len(vault.list_hidden_items(seeded_vault)) == 1

    def test_legacy_id_hide_still_matches_via_alias(self, seeded_vault: Path):
        """A hide stored under the old index-based id must still bite once the
        task reappears with a new numeric id."""
        vault.hide_item(
            seeded_vault,
            item_key="1-ib-myp-i-s-grade-10-homework-1-unit-4",
            title="Homework 1 unit-4",
            subject_name="IB MYP I&S (Grade 10)",
            hidden_at="2026-01-01T00:00:00+00:00",
        )
        assert "Homework 1 unit-4" not in titles(seeded_vault)

    def test_include_hidden_returns_everything(self, seeded_vault: Path):
        vault.hide_task(
            seeded_vault, HOMEWORK_ID, "Homework 1 unit-4",
            "IB MYP I&S (Grade 10)", "2026-09-01T00:00:00+00:00",
        )
        visible, _ = vault.list_tasks(seeded_vault, include_hidden=True)
        assert len(visible) == 3


class TestRecovery:
    def test_recovers_a_hidden_task(self, seeded_vault: Path):
        vault.hide_task(
            seeded_vault, HOMEWORK_ID, "Homework 1 unit-4",
            "IB MYP I&S (Grade 10)", "2026-09-01T00:00:00+00:00",
        )
        assert vault.recover_task(seeded_vault, HOMEWORK_ID) is True
        assert "Homework 1 unit-4" in titles(seeded_vault)

    def test_recovering_an_unhidden_task_reports_false(self, seeded_vault: Path):
        assert vault.recover_task(seeded_vault, "does-not-exist") is False

    def test_recovers_via_the_legacy_key(self, seeded_vault: Path):
        legacy = "1-ib-myp-i-s-grade-10-homework-1-unit-4"
        vault.hide_item(
            seeded_vault, item_key=legacy, title="Homework 1 unit-4",
            subject_name="IB MYP I&S (Grade 10)",
            hidden_at="2026-01-01T00:00:00+00:00",
        )
        assert vault.recover_task(seeded_vault, legacy) is True
        assert "Homework 1 unit-4" in titles(seeded_vault)


class TestPermanentDelete:
    def test_removes_the_task_from_view(self, seeded_vault: Path):
        assert vault.permanently_delete_task(seeded_vault, FORMATIVE_ID) is True
        assert "Formative 1" not in titles(seeded_vault)

    def test_survives_a_rescrape(self, vault_path: Path, payload):
        """Previously 'permanent delete' just un-hid the task, so the next sync
        brought it straight back."""
        vault.ingest_scrape_payload(vault_path, payload)
        vault.permanently_delete_task(vault_path, FORMATIVE_ID)
        vault.ingest_scrape_payload(vault_path, payload)
        assert "Formative 1" not in titles(vault_path)

    def test_second_delete_reports_false(self, seeded_vault: Path):
        assert vault.permanently_delete_task(seeded_vault, FORMATIVE_ID) is True
        assert vault.permanently_delete_task(seeded_vault, FORMATIVE_ID) is False

    def test_deleting_a_hidden_only_row_still_succeeds(self, seeded_vault: Path):
        """A row may exist only as a legacy hide, with no matching task."""
        vault.hide_item(
            seeded_vault, item_key="ghost-id", title="Ghost",
            subject_name="Nowhere", hidden_at="2026-01-01T00:00:00+00:00",
        )
        assert vault.permanently_delete_task(seeded_vault, "ghost-id") is True

    def test_deleted_task_is_excluded_from_subject_counts(self, seeded_vault: Path):
        vault.permanently_delete_task(seeded_vault, FORMATIVE_ID)
        counts = {s["name"]: s["task_count"] for s in vault.list_subjects(seeded_vault)}
        assert counts["IB MYP Mathematics (Grade 10)"] == 0


class TestDrafts:
    def test_save_draft_links_a_matching_task(self, seeded_vault: Path):
        vault.save_draft(
            seeded_vault, task_title="Homework 1 unit-4",
            class_name="IB MYP I&S (Grade 10)", mode="tutor",
            created_at="2026-09-01T00:00:00+00:00", content="# body",
        )
        draft = vault.list_drafts(seeded_vault)[0]
        assert draft["task_id"] is not None

    def test_save_draft_without_a_match_stays_unlinked(self, seeded_vault: Path):
        vault.save_draft(
            seeded_vault, task_title="Nonexistent", class_name="Nowhere",
            mode="tutor", created_at="2026-09-01T00:00:00+00:00", content="# body",
        )
        assert vault.list_drafts(seeded_vault)[0]["task_id"] is None


class TestSyncRuns:
    def test_records_a_run(self, vault_path: Path):
        run_id = vault.start_sync_run(vault_path)
        vault.finish_sync_run(
            vault_path, run_id, status="success", total_items=3,
            parse_errors=0, base_url="https://x", used_auth_state=True,
        )
        last = vault.get_last_sync_run(vault_path)
        assert last["status"] == "success"
        assert last["total_items"] == 3
        assert last["used_auth_state"] is True

    def test_no_run_for_an_untouched_source(self, vault_path: Path):
        assert vault.get_last_sync_run(vault_path, source="kognity") is None

    def test_record_sync_run_keeps_the_given_timestamp(self, vault_path: Path):
        """Backfill must preserve the original scrape time, not stamp 'now'."""
        stamp = "2026-04-29T05:53:25.044198+00:00"
        vault.record_sync_run(
            vault_path, source="managebac", started_at=stamp, status="backfill",
        )
        assert vault.get_last_sync_run(vault_path)["finished_at"] == stamp
