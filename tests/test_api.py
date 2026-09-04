"""The REST surface.

Response shapes matter as much as status codes here: the Flutter client reads
specific keys, and the schema rework was meant to leave them untouched.
"""

from __future__ import annotations

import json
from pathlib import Path

from src import vault

from tests.conftest import make_settings

HOMEWORK_ID = "47949059"

# Exactly what ui/lib/services/api_service.dart reads off each task.
FLUTTER_TASK_KEYS = {"id", "title", "class_name", "due_date", "description"}
FLUTTER_DRAFT_KEYS = {"id", "task_title", "class_name", "mode", "created_at", "content"}


class TestGetTasks:
    def test_returns_seeded_tasks(self, api_client):
        payload = api_client.get("/tasks").json()
        assert len(payload["tasks"]) == 3

    def test_keeps_every_key_the_flutter_client_reads(self, api_client):
        task = api_client.get("/tasks").json()["tasks"][0]
        assert FLUTTER_TASK_KEYS <= set(task)

    def test_exposes_the_stable_id(self, api_client):
        ids = {t["id"] for t in api_client.get("/tasks").json()["tasks"]}
        assert HOMEWORK_ID in ids

    def test_metadata_reports_counts(self, api_client):
        meta = api_client.get("/tasks").json()["metadata"]
        assert meta["total_tasks"] == 3
        assert meta["visible_tasks"] == 3
        assert meta["hidden_tasks"] == 0

    def test_unknown_source_is_rejected(self, api_client):
        assert api_client.get("/tasks", params={"source": "bogus"}).status_code == 400

    def test_kognity_is_known_but_empty(self, api_client):
        payload = api_client.get("/tasks", params={"source": "kognity"}).json()
        assert payload["tasks"] == []
        assert payload["metadata"]["sync_status"] == "not_configured"


class TestHideRecoverDelete:
    def hide(self, client, task):
        return client.post(
            "/tasks/hide",
            json={
                "task_id": task["id"],
                "task_title": task["title"],
                "class_name": task["class_name"],
            },
        )

    def test_hide_removes_it_from_the_list(self, api_client):
        task = api_client.get("/tasks").json()["tasks"][0]
        assert self.hide(api_client, task).status_code == 200

        payload = api_client.get("/tasks").json()
        assert task["id"] not in {t["id"] for t in payload["tasks"]}
        assert payload["metadata"]["hidden_tasks"] == 1

    def test_hidden_list_uses_the_same_shape(self, api_client):
        task = api_client.get("/tasks").json()["tasks"][0]
        self.hide(api_client, task)
        hidden = api_client.get("/tasks/hidden").json()["tasks"]
        assert FLUTTER_TASK_KEYS <= set(hidden[0])

    def test_recover_restores_it(self, api_client):
        task = api_client.get("/tasks").json()["tasks"][0]
        self.hide(api_client, task)
        assert api_client.post(
            "/tasks/recover", json={"task_id": task["id"]}
        ).status_code == 200
        assert len(api_client.get("/tasks").json()["tasks"]) == 3

    def test_recovering_an_unhidden_task_is_404(self, api_client):
        response = api_client.post("/tasks/recover", json={"task_id": "nope"})
        assert response.status_code == 404

    def test_permanent_delete_removes_it(self, api_client):
        task = api_client.get("/tasks").json()["tasks"][0]
        response = api_client.request(
            "DELETE", "/tasks/permanent", json={"task_id": task["id"]}
        )
        assert response.status_code == 200
        assert len(api_client.get("/tasks").json()["tasks"]) == 2

    def test_deleting_twice_is_404(self, api_client):
        task = api_client.get("/tasks").json()["tasks"][0]
        api_client.request("DELETE", "/tasks/permanent", json={"task_id": task["id"]})
        second = api_client.request(
            "DELETE", "/tasks/permanent", json={"task_id": task["id"]}
        )
        assert second.status_code == 404

    def test_blank_ids_are_rejected(self, api_client):
        assert api_client.post("/tasks/recover", json={"task_id": "  "}).status_code == 400
        assert api_client.post(
            "/tasks/hide",
            json={"task_id": "x", "task_title": " ", "class_name": "c"},
        ).status_code == 400


class TestSubjectsAndSync:
    def test_lists_subjects_with_counts(self, api_client):
        subjects = api_client.get("/subjects").json()["subjects"]
        assert len(subjects) == 3
        assert all("task_count" in s for s in subjects)

    def test_counts_drop_when_a_task_is_deleted(self, api_client):
        task = api_client.get("/tasks").json()["tasks"][0]
        api_client.request("DELETE", "/tasks/permanent", json={"task_id": task["id"]})

        subjects = {s["name"]: s["task_count"] for s in
                    api_client.get("/subjects").json()["subjects"]}
        assert subjects[task["class_name"]] == 0

    def test_sync_status_covers_both_platforms(self, api_client):
        sources = {s["source"]: s for s in api_client.get("/sync/status").json()["sources"]}
        assert set(sources) == {"managebac", "kognity"}

    def test_kognity_reports_not_configured(self, api_client):
        sources = {s["source"]: s for s in api_client.get("/sync/status").json()["sources"]}
        assert sources["kognity"]["status"] == "not_configured"


class TestVault:
    def test_draft_shape_is_unchanged(self, api_client, seeded_vault: Path):
        vault.save_draft(
            seeded_vault, task_title="Homework 1 unit-4",
            class_name="IB MYP I&S (Grade 10)", mode="tutor",
            created_at="2026-09-01T00:00:00+00:00", content="# body",
        )
        drafts = api_client.get("/vault").json()["drafts"]
        assert FLUTTER_DRAFT_KEYS <= set(drafts[0])

    def test_draft_file_route_404s_when_absent(self, api_client):
        response = api_client.get("/tasks/Some Class/Some Task/draft")
        assert response.status_code == 404


class TestBackfill:
    def test_seeds_an_empty_vault_from_the_scrape_file(
        self, tmp_path: Path, payload, vault_path: Path
    ):
        """A vault predating the rework would otherwise look empty until the
        next scrape."""
        from fastapi.testclient import TestClient

        from src import api

        tasks_json = tmp_path / "tasks_raw.json"
        tasks_json.write_text(json.dumps(payload), encoding="utf-8")

        settings = make_settings(tmp_path, vault_path, tasks_output_path=tasks_json)
        api._get_settings.cache_clear()
        original = api._get_settings
        api._get_settings = lambda: settings
        try:
            with TestClient(api.app) as client:
                body = client.get("/tasks").json()
                assert len(body["tasks"]) == 3
                # The original scrape time is preserved, not the backfill time.
                assert body["metadata"]["scraped_at"] == \
                    payload["metadata"]["scraped_at"]
                assert body["metadata"]["sync_status"] == "backfill"
        finally:
            api._get_settings = original
            api._get_settings.cache_clear()

    def test_does_not_run_twice(self, tmp_path: Path, payload, vault_path: Path):
        from fastapi.testclient import TestClient

        from src import api

        tasks_json = tmp_path / "tasks_raw.json"
        tasks_json.write_text(json.dumps(payload), encoding="utf-8")
        settings = make_settings(tmp_path, vault_path, tasks_output_path=tasks_json)
        api._get_settings.cache_clear()
        original = api._get_settings
        api._get_settings = lambda: settings
        try:
            for _ in range(2):
                with TestClient(api.app) as client:
                    client.get("/tasks")
            assert len(vault.list_tasks(vault_path)[0]) == 3
        finally:
            api._get_settings = original
            api._get_settings.cache_clear()
