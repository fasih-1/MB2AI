"""Schema v0 -> v1 migration.

This is the code that runs against the user's real vault.db, in place, on
first launch after an upgrade. It is currently protected in production only by
the backup it writes, so it gets the most coverage here.
"""

from __future__ import annotations

import sqlite3
from pathlib import Path

from src import vault

EXPECTED_TABLES = {
    "subjects",
    "tasks",
    "task_attachments",
    "content_blocks",
    "hidden_items",
    "sync_runs",
    "drafts",
}


def table_names(path: Path) -> set[str]:
    connection = sqlite3.connect(path)
    try:
        return {
            row[0]
            for row in connection.execute(
                "SELECT name FROM sqlite_master WHERE type='table'"
            )
        }
    finally:
        connection.close()


def user_version(path: Path) -> int:
    connection = sqlite3.connect(path)
    try:
        return connection.execute("PRAGMA user_version").fetchone()[0]
    finally:
        connection.close()


class TestFreshDatabase:
    def test_creates_every_table(self, vault_path: Path):
        vault._ensure_db(vault_path)
        assert EXPECTED_TABLES <= table_names(vault_path)

    def test_stamps_schema_version(self, vault_path: Path):
        vault._ensure_db(vault_path)
        assert user_version(vault_path) == vault.SCHEMA_VERSION

    def test_creates_parent_directory(self, tmp_path: Path):
        nested = tmp_path / "does" / "not" / "exist" / "vault.db"
        vault._ensure_db(nested)
        assert nested.exists()

    def test_no_backup_written_for_a_new_database(self, vault_path: Path):
        vault._ensure_db(vault_path)
        assert not vault_path.with_suffix(".db.bak-pre-v1").exists()


class TestLegacyMigration:
    def test_preserves_drafts(self, legacy_vault: Path):
        vault._ensure_db(legacy_vault)
        drafts = vault.list_drafts(legacy_vault)
        assert len(drafts) == 2
        assert {d["task_title"] for d in drafts} == {
            "Homework 1 unit-4",
            "Summative Task 1",
        }

    def test_adds_nullable_task_id_to_drafts(self, legacy_vault: Path):
        vault._ensure_db(legacy_vault)
        # Column exists, and pre-existing rows are simply unlinked.
        assert all(d["task_id"] is None for d in vault.list_drafts(legacy_vault))

    def test_carries_hidden_tasks_into_hidden_items(self, legacy_vault: Path):
        vault._ensure_db(legacy_vault)
        hidden = vault.list_hidden_items(legacy_vault)
        assert {h["item_key"] for h in hidden} == {
            "2-ib-myp-biology-grade-10-summative-task-1",
            "1-ib-myp-design-grade-10-class-task",
        }

    def test_computes_alias_keys_for_legacy_hides(self, legacy_vault: Path):
        """The legacy ids are index-based and will never match a new id.

        The alias is what keeps those hides working after the id scheme change.
        """
        vault._ensure_db(legacy_vault)
        hidden = {h["item_key"]: h for h in vault.list_hidden_items(legacy_vault)}
        row = hidden["2-ib-myp-biology-grade-10-summative-task-1"]
        assert row["alias_key"] == vault.alias_key_for(
            "IB MYP Biology (Grade 10)", "Summative Task 1"
        )

    def test_keeps_legacy_table_as_a_safety_net(self, legacy_vault: Path):
        vault._ensure_db(legacy_vault)
        assert "hidden_tasks" in table_names(legacy_vault)

    def test_writes_a_backup(self, legacy_vault: Path):
        vault._ensure_db(legacy_vault)
        backup = legacy_vault.with_suffix(legacy_vault.suffix + ".bak-pre-v1")
        assert backup.exists() and backup.stat().st_size > 0

    def test_backup_is_the_pre_migration_database(self, legacy_vault: Path):
        vault._ensure_db(legacy_vault)
        backup = legacy_vault.with_suffix(legacy_vault.suffix + ".bak-pre-v1")
        assert table_names(backup) == {"drafts", "hidden_tasks", "sqlite_sequence"}
        assert user_version(backup) == 0


class TestIdempotence:
    def test_running_twice_changes_nothing(self, legacy_vault: Path):
        vault._ensure_db(legacy_vault)
        vault._migrated_paths.clear()
        vault._ensure_db(legacy_vault)

        assert len(vault.list_drafts(legacy_vault)) == 2
        assert len(vault.list_hidden_items(legacy_vault)) == 2

    def test_does_not_overwrite_an_existing_backup(self, legacy_vault: Path):
        vault._ensure_db(legacy_vault)
        backup = legacy_vault.with_suffix(legacy_vault.suffix + ".bak-pre-v1")
        backup.write_bytes(b"sentinel")

        vault._migrated_paths.clear()
        vault._ensure_db(legacy_vault)

        assert backup.read_bytes() == b"sentinel"

    def test_already_current_database_is_left_alone(self, seeded_vault: Path):
        before = user_version(seeded_vault)
        vault._migrated_paths.clear()
        vault._ensure_db(seeded_vault)
        assert user_version(seeded_vault) == before
        assert len(vault.list_tasks(seeded_vault)[0]) == 3


class TestDraftLinking:
    def test_ingest_links_orphan_drafts_to_their_task(
        self, legacy_vault: Path, payload
    ):
        """A draft written before the vault knew about tasks gets linked once
        a matching task is ingested."""
        vault._ensure_db(legacy_vault)
        assert all(d["task_id"] is None for d in vault.list_drafts(legacy_vault))

        payload["tasks"][0]["class_name"] = "IB MYP I&S (Grade 10)"
        vault.ingest_scrape_payload(legacy_vault, payload)

        linked = {
            d["task_title"]: d["task_id"] for d in vault.list_drafts(legacy_vault)
        }
        assert linked["Homework 1 unit-4"] is not None
        # No task matches this draft, so it stays unlinked rather than guessing.
        assert linked["Summative Task 1"] is None

    def test_draft_keeps_its_denormalized_columns(self, legacy_vault: Path):
        """Drafts must survive their task disappearing from ManageBac."""
        vault._ensure_db(legacy_vault)
        draft = vault.list_drafts(legacy_vault)[0]
        assert draft["task_title"] and draft["class_name"]
