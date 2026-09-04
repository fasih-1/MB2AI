# MB2AI — Project Brief & Architecture Plan

This file exists so Claude Code has full context on the project without the user needing to re-explain it. Read this before making changes.

## What MB2AI Is

A local-first desktop app that bridges school platforms with LLMs. It scrapes assignment/task data, pairs it with syllabus/reference context, and routes structured prompts to an LLM for study planning and drafting — while respecting academic honesty (it should help students understand and plan, not just generate work to submit as-is).

Original repo: https://github.com/fasih-1/MB2AI (existing v3 implementation, being extended and modernized — not a from-scratch rewrite unless a section below says so).

## Why This Rebuild

The school is transitioning from ManageBac-only to a mixed ManageBac + Kognity setup (IB DP, Grade 11):
- **ManageBac** = administrative/evaluation hub: deadlines, task briefs, rubric criteria (A–D), IAs.
- **Kognity** = curriculum/content hub: interactive textbooks, syllabus sub-topics, practice questions.

The value of bridging both: ManageBac gives the rubric, Kognity gives the actual syllabus content to draft against — right now those live in two disconnected places.

Secondary goal: modernize the UI/UX into something simpler and more maintainable. This was originally a structural problem — a single 1,642-line `dashboard.dart` — which has since been split up (see Implementation Status).

## Current Kognity Status (checked manually, September 2026)

As of now, the user's Kognity account has **no populated content** — no practice questions, and no textbook/reading content loaded into subjects yet. The school appears to be mid-rollout: the platform exists but teachers haven't populated it. This was confirmed by manually logging in and checking (no DevTools/API scoping was possible since there's nothing being fetched).

**Implication:** Do not build the Kognity ingestion worker yet — there's nothing to ingest, and any API/selector work done now would be built against a state that won't reflect the real, populated platform. Instead:
- Build the schema and backend to be **multi-source-ready** (a `source` field, room for a `content_blocks` table) without actually implementing Kognity ingestion. **Done** — see Implementation Status.
- Proceed ManageBac-first for this build cycle.
- Revisit the Kognity spike (see "Build Order") once the user confirms content has appeared — that's an external trigger (school populating the platform), not something to schedule on a timeline.

---

## Implementation Status

Steps 1–3 of the build order are **built and committed**. What follows describes the code as it actually is.

### Tech stack
- Frontend: Flutter Desktop (Windows target), **dark theme**, physics-based micro-interactions (hover-scale, morphing buttons)
- Backend: Python 3.11+, FastAPI + Uvicorn, communicates over `127.0.0.1` loopback
- Scraping: Playwright
- Local persistence: SQLite (`vault.db`)

> Note on the theme: this file previously said "dark-mode" while the app actually shipped a light palette (`#FAFBFD`, `Brightness.light`). The user resolved this in favour of **dark**, and the app was rebuilt on a dark palette. `theme/app_theme.dart` is now the single source of colour truth.

### Data model — built (`src/vault.py`, schema v1)

Migrations run off `PRAGMA user_version`; `_ensure_db` upgrades in place and writes a `vault.db.bak-pre-v1` snapshot first (those snapshots are gitignored).

- `subjects` — id, source, source_subject_id, name, ib_level, grade. `UNIQUE(source, name)`.
- `tasks` — ManageBac-sourced, `source='managebac'`. Carries summary/full_description/due_date, a best-effort badge parse (`task_type`, `category`, `weight`, `status`), `rubric_criteria` (JSON, **not yet populated**), `first_seen_at`/`last_seen_at`, and `deleted_at` for soft deletes. `UNIQUE(source, source_task_id)`.
- `task_attachments` — project-relative paths, so the vault survives the repo moving on disk. `extracted_text` reserved, unused.
- `content_blocks` — **placeholder for Kognity. Created empty; nothing reads or writes it.** Deliberately thin: its real shape is decided after the ingestion spike.
- `drafts` — gained a nullable `task_id`. Keeps denormalized `task_title`/`class_name` so a draft survives its task disappearing from ManageBac.
- `hidden_items` — generalizes the old `hidden_tasks` with `item_type` and an `alias_key`.
- `sync_runs` — per-source run history; backs `/tasks` metadata and `/sync/status`.

The legacy `hidden_tasks` table is intentionally **left in place** as a safety net and should be dropped in a schema v2 once the migration is trusted.

**Task identity:** derived from the numeric id in the ManageBac assignment URL (`core_tasks/(\d+)`), falling back to a `sha1(class::title)` hash. The previous scheme hashed in the row's *list index*, so every id changed when the dashboard re-ordered — which is why hides used to break. `hidden_items.alias_key` carries content-derived keys so hides made under the old scheme still match.

### API surface — `src/api.py`
`/tasks` (accepts `?source=`), `/tasks/hidden`, `/tasks/hide|recover|permanent`, `/subjects`, `/sync/status`, `/vault`, `/scrape`, `/generate`, `/tasks/{class}/{title}/draft`, `/ws/logs`. All task endpoints read SQLite; `tasks_raw.json` is now a scrape artifact rather than the source of truth.

`DELETE /tasks/permanent` sets `deleted_at` so the task stays gone across re-scrapes. It previously just un-hid the task, which meant it reappeared on the next sync.

Response shapes keep every key the Flutter client already read, so the schema rework needed no UI changes.

### LLM providers — `src/providers.py`
`LLMProvider` base class owns the retry/backoff loop (tuned for free-tier rate limits; auth errors raise `LLMAuthError` and are never retried).
- **Groq** — ~30 req/min, fast, small context. The default for tutor-mode outlining.
- **Gemini** — ~15 req/min, ~500/day, large context, via the `google-genai` SDK.

`ProviderRouter` routes by prompt size: below `LLM_LARGE_CONTEXT_CHARS` (default 12000) → Groq, at or above → Gemini. With only one key configured everything routes to it, so **Gemini is optional**. `LLM_PROVIDER=auto|groq|gemini` pins a backend.

Two limits are provider properties rather than constants: `max_description_chars` (Groq 1500, Gemini 60000) and `pacing_seconds` (Groq 15, Gemini 4). Routing measures the *untruncated* prompt, since its full size is the honest measure of how much context a task needs.

`brain.py` takes a list of task dicts and no longer reads a file; callers load from the vault, so **generation honours hides and permanent deletes**. Its prompt text and the tutor/ghostwriter split are unchanged.

### Frontend — `ui/lib/`
`dashboard.dart` went 1,642 → 687 lines and now owns only state and API calls. Presentation lives in `theme/app_theme.dart` plus `widgets/`: `top_bar.dart`, `task_sidebar.dart`, `task_card.dart`, `generation_controls.dart`, `mode_selector.dart`, `draft_view.dart`, `ambient_background.dart`, `staggered_entrance.dart`, `vault_history_dialog.dart`, `debug_console.dart`.

Layout: a slim toolbar holds only always-valid actions (scrape, vault, log console); instructions and the attachment picker sit behind an expander; the generation bar renders **only with a task selected**, so no control is shown that cannot act on anything.

On a dark ground drop shadows read as mud, so depth comes from a three-step surface ramp (`#0D1117` / `#161B22` / `#1C2331`) plus borders, and emphasis from an accent glow.

### Environment (`.env`)
`MANAGEBAC_USERNAME` / `PASSWORD` / `BASE_URL`, `GROQ_API_KEY` / `GROQ_MODEL`, optional `GEMINI_API_KEY` / `GEMINI_MODEL`, `LLM_PROVIDER`, `LLM_LARGE_CONTEXT_CHARS`, plus paths. `.env.example` documents all of it. A second platform's credentials/auth state are **not** needed until the Kognity work starts.

### Tests
`ui/test/widget_test.dart` (app shell) and `ui/test/layout_test.dart` (toolbar and generation bar across five widths, collapsed and expanded) — 16 tests, run with `flutter test` from `ui/`.

**There are no Python tests.** The vault migration, task-identity derivation, and provider routing were verified by ad-hoc scripts, not a committed suite. This is the largest coverage gap: the migration runs against live data and is currently protected only by its backup file.

---

## Still To Do

### Open threads from the completed steps
- **`rubric_criteria` has no source.** The column exists and defaults to `[]`; `parser.py` does not extract MYP criteria A–D from the assignment page. This is the one *active* question from the original brief.
- **Scraped attachments are not used.** `task_attachments` is populated on every scrape, but `/generate` still requires the user to re-upload a file the scraper already downloaded. Wiring it means passing extracted text into `brain.py`'s existing `source_document_context` parameter — no prompt-logic change.
- **Gemini has never made a live call.** No `GEMINI_API_KEY` is set, so the real request path is unproven.
- **No Python test suite** (see above).
- **`data/pending_review/` and `data/attachments/`** are untracked but not gitignored — generated drafts and scraped PDFs sitting in the working tree.

### Build order — remaining
1. ~~Schema + backend models~~ — **done**
2. ~~LLM provider abstraction (Groq + Gemini)~~ — **done**
3. ~~Flutter UI refactor and redesign~~ — **done**
4. **(Deferred) Kognity ingestion spike** — only once the user confirms Kognity has content. Then: log in, inspect network requests via DevTools, determine whether a JSON/GraphQL API exists, extend `content_blocks`, and build the worker. Gated on an external event, not on dev progress.
5. **(Deferred) Auth worker split** — a second independent auth worker (`auth_state_kognity.json`, per-platform "needs re-login" status) only becomes necessary once step 4 happens. `sync_runs` and `/sync/status` already exist to surface per-platform state. Until then, single-platform ManageBac auth is sufficient.

### Ingestion strategy (unchanged, for when step 4 arrives)
- **ManageBac**: keep the existing Playwright + `selectors.py` approach — it works. `sync_runs` now records a `partial` status when the task container is missing, which is the guard against the selector-drift incident that produced `data/debug_zero_tasks.png`.
- **Kognity**: unknown. Modern SPA ed-tech platforms usually call a JSON or GraphQL API under the hood. Investigate via DevTools → Network before writing any scraper; hit the API directly with the authenticated session cookie if one exists, and fall back to Playwright + selectors only if not.

## Open Questions
- (Deferred until Kognity has content) Does Kognity expose a JSON/GraphQL API, or is a full Playwright scrape unavoidable?
- (Deferred) What specific Kognity data is worth ingesting — full textbook text, section summaries, syllabus sub-topic titles, practice question metadata?
- (Deferred) Final `content_blocks` schema shape.
- (Deferred) Whether Kognity's login is standard form-based or SAML/SSO.
- **Grade/programme mismatch:** this brief describes IB DP Grade 11, but `brain.py`'s system prompt hard-codes *"an elite IB MYP 5 Study Assistant"* and the scraped data in the vault is MYP Grade 10. Worth confirming which programme the prompts should target before the next generation-quality pass. Prompt text has deliberately not been changed.
