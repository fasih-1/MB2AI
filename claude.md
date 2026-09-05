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
- Frontend: Flutter Desktop (Windows target), **dark theme with a user-settable accent colour**, physics-based micro-interactions (hover-scale, morphing buttons)
- Backend: Python 3.11+, FastAPI + Uvicorn, communicates over `127.0.0.1` loopback
- Scraping: Playwright
- Local persistence: SQLite (`vault.db`)

> Note on the theme: this file previously said "dark-mode" while the app actually shipped a light palette (`#FAFBFD`, `Brightness.light`). The user resolved this in favour of dark. That first dark pass then went through a further redesign — three visual directions were drafted on a Claude Design canvas (warm/analog, bold/editorial-dark, playful/colourful), the user picked a mix of the latter two, and that became the current implementation, described under Frontend below. `theme/app_theme.dart` is the single source of colour truth; nothing else should hardcode a colour.

### Data model — built (`src/vault.py`, schema v1)

Migrations run off `PRAGMA user_version`; `_ensure_db` upgrades in place and writes a `vault.db.bak-pre-v1` snapshot first (those snapshots are gitignored).

- `subjects` — id, source, source_subject_id, name, ib_level, grade. `UNIQUE(source, name)`.
- `tasks` — ManageBac-sourced, `source='managebac'`. Carries summary/full_description/due_date, a best-effort badge parse (`task_type`, `category`, `weight`, `status`), `rubric_criteria` (JSON, populated from task text — see Assessment criteria), `first_seen_at`/`last_seen_at`, and `deleted_at` for soft deletes. `UNIQUE(source, source_task_id)`.
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

**Both backends are now confirmed working with a real call** — `GROQ_MODEL=openai/gpt-oss-20b`, `GEMINI_MODEL=gemini-3.6-flash`. Two unrelated things had to be fixed to get there, both worth knowing about since the pattern will recur:
- **TLS**: this dev machine's antivirus intercepts HTTPS and presents its own certificate, which Python's default certifi-based verification rejects — every call failed with `CERTIFICATE_VERIFY_FAILED` before `src/tls.py` (`enable_system_trust_store`, called at API and CLI startup) routed verification through the OS trust store instead.
- **Model churn**: both `GROQ_MODEL` and `GEMINI_MODEL` had drifted onto decommissioned model ids (`llama-3.3-70b-versatile`, `gemini-2.0-flash`) since this file was first written. Groq's error for a dead model is a **misleading 403** whose message says "Access denied. Please check your network settings" — nothing to do with networking, so don't chase a network/region-block theory when that specific message shows up; go straight to `GET /openai/v1/models` with the account's key to see what it actually serves. Gemini's 404 is more honest and names the replacement directly. Both providers retire models on their own schedule — expect to redo this occasionally, and check the provider's current model list rather than assuming the pinned id still exists.

### Frontend — `ui/lib/`
`dashboard.dart` went 1,642 → ~700 lines and now owns only state and API calls. Presentation lives in `theme/app_theme.dart` plus `widgets/`: `top_bar.dart`, `task_sidebar.dart`, `task_card.dart`, `generation_controls.dart`, `mode_selector.dart`, `draft_view.dart`, `meta_badge.dart`, `ambient_background.dart`, `staggered_entrance.dart`, `vault_history_dialog.dart`, `debug_console.dart`.

Layout: a slim toolbar holds only always-valid actions (scrape, vault, accent colour, log console); instructions and the attachment picker sit behind an expander; the generation bar renders **only with a task selected**, so no control is shown that cannot act on anything.

**Theme**: a warm charcoal/violet dark palette (`#14111C` / `#1B1726` / `#241F33` surface ramp), Bricolage Grotesque for headers and IBM Plex Sans for body text via `google_fonts` (fetched at runtime — needs network on first launch, same as the rest of the app already does). This came out of a Claude Design canvas exploring three directions; the user picked a mix of the dark/editorial one and the colourful/card-based one.

**Accent colour is a user setting, not a constant.** `theme/accent_color_controller.dart` is a `ChangeNotifier` holding the chosen `Color`, persisted via `shared_preferences` and loaded before the first frame; `main.dart` wraps `MaterialApp` in a `ListenableBuilder` so the whole theme rebuilds on change. `buildAppTheme()` takes that colour and derives everything from it — hover/press variants, the glow, and the text/icon colour drawn on a filled button, via a real contrast check (`onAccentFor`) rather than assuming dark-on-light always works (a white or saturated-red accent still needs readable button text). The picker itself is a swatch button in `TopBar` (Purple/Blue/Red/Green/Amber/White). No widget should read a fixed accent colour any more — use `Theme.of(context).colorScheme.primary`.

**Subject identity colouring**: `TaskCard` shows a coloured icon chip per task, derived from the subject name via `subjectColorFor`/`subjectIconFor` (a stable hash into a small fixed palette, so the same subject always lands on the same colour regardless of list order — collisions between subjects are possible with a small palette and are an accepted tradeoff, not a bug, since the icon shape still disambiguates). The one exception: the *selected* task's chip borrows the app's accent colour instead of its subject colour, so the task you're looking at also matches the rest of the UI.

On a dark ground drop shadows read as mud, so depth comes from the surface ramp plus borders, and emphasis from an accent glow computed from whatever colour is currently chosen.

### Environment (`.env`)
`MANAGEBAC_USERNAME` / `PASSWORD` / `BASE_URL`, `GROQ_API_KEY` / `GROQ_MODEL`, optional `GEMINI_API_KEY` / `GEMINI_MODEL`, `LLM_PROVIDER`, `LLM_LARGE_CONTEXT_CHARS`, plus paths. `.env.example` documents all of it. A second platform's credentials/auth state are **not** needed until the Kognity work starts.

### Packaging a standalone build
`python -m src.main --serve` and `flutter run -d windows` are for development; a real double-click distributable is `brain.spec` (PyInstaller, onefile) plus `flutter build windows --release`, both copied into one folder alongside a launcher batch file. Three non-obvious bugs had to be fixed to make that actually work, all worth knowing before touching `brain.spec` again:
- **Build with `.venv`'s Python, not the global one.** This project's real dependencies (fastapi, uvicorn, groq, google-genai, playwright, ...) are only installed in `.venv`; running `pyinstaller` under the global interpreter silently produces an exe that imports none of them (`ModuleNotFoundError: No module named 'fastapi'` at runtime, even though the build itself reports success). Always build with `./.venv/Scripts/python.exe -m PyInstaller brain.spec`.
- **`src.api` has to be a hidden import.** `main.py` starts the server as `uvicorn.run("src.api:app", ...)` — a string uvicorn resolves dynamically — so PyInstaller's static analysis never sees that `src/api.py` (and everything it imports) needs bundling. `brain.spec`'s `hiddenimports` now includes `'src.api'` explicitly, plus `collect_submodules('uvicorn')` since uvicorn also chooses its event-loop/protocol backend dynamically.
- **`project_root` can't come from `Path(__file__)` in a frozen build.** Inside a PyInstaller onefile exe, `__file__` resolves into the temp extraction directory, not next to the shipped exe — so a packaged app would silently create a fresh empty `vault.db` and never find `.env`. `config.py`'s `load_settings` now checks `sys.frozen` and uses `Path(sys.executable).resolve().parent` instead, so `.env` and `vault.db` must sit next to `brain.exe` in the packaged folder (copy both in manually; neither is bundled inside the exe).

`build/` (PyInstaller's intermediate cache) and `dist/` (the actual output, including `.env`/`vault.db` copies) are both gitignored — a distributable folder is assembled locally and is never something to commit or share as-is, since it contains real API keys.

### Assessment criteria — `src/rubric.py`
`tasks.rubric_criteria` is filled from the task text, not from new selectors. Real briefs write "Criterion B: Investigating", so `extract_criteria` handles both named forms and bare lists ("Criteria A and B"), restricted to A–D.

Ingestion fills it from the task description; the attachment pass merges in anything the attached brief names, since criteria are often only there. A re-scrape that finds none will not wipe what an attachment supplied.

This is text-derived on purpose: criteria are not exposed as structured data anywhere the scraper reaches, and there is no saved assignment-detail markup to write selectors against. **If a DOM source is ever confirmed on a real summative task page, prefer it and keep this as the fallback.**

### Tests
- **Python: 203 tests**, `pytest` from the repo root. Covers the schema migration, task identity, ingestion, hide/recover/delete, provider routing and retry, generation, attachments, criteria extraction, the false-positive attachment-selector fix, TLS trust-store injection, and the REST surface. Every test uses a temporary database and builds `Settings` directly, so the suite touches neither the real `vault.db` nor `.env`, and makes no network calls.
- **Flutter: 31 tests**, `flutter test` from `ui/`. App shell, toolbar/generation-bar overflow across five widths, task metadata badges, and the accent-colour picker (open → pick a swatch → controller updates and persists; a selected card borrows the accent while an unselected one keeps its subject colour). The picker tests exist because OS-level synthetic clicks stopped registering partway through one session for reasons unrelated to the app — if that recurs, verify interactive Flutter behaviour through `flutter test`'s own tap simulation rather than screenshot-and-click automation.

Test-only dependencies live in `requirements-dev.txt`.

---

## Still To Do

### Known gaps, not yet scheduled
- `parser.py` still does not read criteria from the assignment DOM; see the note under Assessment criteria. Text-derived extraction is the deliberate fallback until a real summative task page can be inspected.
- The legacy `hidden_tasks` table is still present, pending a schema v2 that drops it.
- The accent-colour swatch list (Purple/Blue/Red/Green/Amber/White) is fixed in `app_theme.dart`; a full colour-wheel picker was judged unnecessary for a six-choice setting, but revisit if the user asks for an arbitrary colour.

### Resolved
The two items previously listed here — no LLM backend had made a live call, and coursework/drafts were reachable in git history — are both closed: both Groq and Gemini are confirmed working with real calls (see LLM providers above), and the git history was rewritten (`git filter-repo`, force-pushed) to remove the coursework; the pre-rewrite history is backed up outside the repo. The UI also now surfaces `rubric_criteria`/`task_type`/`category`/`weight`/`status` via `MetaBadge`, so that gap is closed too.

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
- **Grade/programme mismatch:** this brief describes IB DP Grade 11, and `brain.py`'s system prompt hard-codes *"an elite IB MYP 5 Study Assistant."* The vault held only MYP Grade 10 tasks for most of this build cycle, but a live scrape has since picked up two DP Grade 11 Math tasks alongside them — the transition this brief describes is genuinely starting. One of those tasks' instructions read *"Do the homework on Kognity.com,"* which is also the first live signal that Kognity may now have content; worth checking manually. Once the vault is consistently DP-Grade-11, revisit whether the MYP-specific prompt wording still fits. Prompt text has deliberately not been changed.
