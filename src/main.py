from __future__ import annotations

import asyncio
import argparse
import sys

import uvicorn

from src.brain import generate_drafts_from_tasks
from src.config import load_settings
from src.logger import setup_logger
from src.scraper import Scraper


def _parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="MB2AI automation runner")
    parser.add_argument(
        "--debug",
        action="store_true",
        help="Run in headed debug mode and wait after submitting login credentials.",
    )
    parser.add_argument(
        "--headed",
        action="store_true",
        help="Run browser in headed mode (non-headless).",
    )
    parser.add_argument(
        "--generate",
        action="store_true",
        help="Run Phase 2 generation over existing data/tasks_raw.json.",
    )
    parser.add_argument(
        "--mode",
        default="tutor",
        help="Generation mode for --generate (tutor or ghostwriter).",
    )
    parser.add_argument(
        "--serve",
        action="store_true",
        help="Run the FastAPI bridge on 127.0.0.1:8000.",
    )
    return parser.parse_args()


async def _run(args: argparse.Namespace) -> int:
    settings = load_settings(force_headed=(args.headed or args.debug), debug_mode=args.debug)
    logger = setup_logger(settings.project_root)

    if args.generate:
        output_base = settings.project_root / "data" / "pending_review"
        summary = generate_drafts_from_tasks(
            tasks_path=settings.tasks_output_path,
            output_base=output_base,
            api_key=settings.groq_api_key,
            model_name=settings.groq_model,
            mode=args.mode,
            logger=logger,
        )
        logger.info(
            "GENERATION_SUMMARY generated=%s skipped=%s failed=%s",
            summary["generated"],
            summary["skipped"],
            summary["failed"],
        )
        return 0

    scraper = Scraper(settings=settings, logger=logger)

    output_path = await scraper.run()
    logger.info("Wrote task output to %s", output_path)
    return 0


def main() -> int:
    try:
        args = _parse_args()
        if args.serve:
            uvicorn.run("src.api:app", host="127.0.0.1", port=8000)
            return 0
        return asyncio.run(_run(args))
    except Exception as exc:
        print(f"MB2AI failed: {exc}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
