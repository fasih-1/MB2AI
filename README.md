# MB2AI - Phase 1

Phase 1 implements ManageBac task scraping with Playwright.

## Quick Start (Windows)

1. Create a virtual environment and activate it.
2. Install dependencies from requirements.txt.
3. Install browser binaries for Playwright.
4. Copy .env.example to .env and fill your credentials.
5. Run: python -m src.main

## Debug / Headed Mode

- Headed only: python -m src.main --headed
- Headed + debug diagnostics: python -m src.main --debug

## Phase 2 Generation

- Generate tutor drafts from existing data/tasks_raw.json: python -m src.main --generate
- Requires GEMINI_API_KEY in .env.
- Output markdown files are saved under data/pending_review/{class_name}/.

After login submit, the scraper performs a short non-blocking check to auto-dismiss
common popup buttons like Accept, Accept All Cookies, Agree, or Close.

If no tasks are detected, it saves:
- data/debug_zero_tasks.png
- data/debug_page.html

## Output

- data/auth_state.json: saved browser auth state.
- data/tasks_raw.json: structured scraped task data.
- logs/scraper.log: run logs and retry details.

## Notes

- Keep .env private.
- If selectors break due to UI changes, update src/selectors.py.
