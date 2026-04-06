from __future__ import annotations

import asyncio
import logging
from pathlib import Path


class AsyncQueueHandler(logging.Handler):
    """Forward selected log records into an asyncio queue on a target loop."""

    def __init__(self, queue: asyncio.Queue[str], loop: asyncio.AbstractEventLoop) -> None:
        super().__init__(level=logging.INFO)
        self.queue = queue
        self.loop = loop

    def emit(self, record: logging.LogRecord) -> None:
        if record.levelno not in (logging.INFO, logging.WARNING, logging.ERROR):
            return

        try:
            message = self.format(record)
        except Exception:
            self.handleError(record)
            return

        def _enqueue() -> None:
            if self.queue.full():
                try:
                    self.queue.get_nowait()
                except asyncio.QueueEmpty:
                    pass
            try:
                self.queue.put_nowait(message)
            except asyncio.QueueFull:
                # A race can still fill the queue between checks; dropping newest keeps logger non-blocking.
                return

        try:
            self.loop.call_soon_threadsafe(_enqueue)
        except RuntimeError:
            # Event loop is likely shutting down.
            return


def setup_logger(
    project_root: Path,
    log_queue: asyncio.Queue[str] | None = None,
    event_loop: asyncio.AbstractEventLoop | None = None,
) -> logging.Logger:
    logs_dir = project_root / "logs"
    logs_dir.mkdir(parents=True, exist_ok=True)

    logger = logging.getLogger("mb2ai")
    logger.setLevel(logging.INFO)

    formatter = logging.Formatter(
        "[%(levelname)s] [%(asctime)s] %(name)s - %(message)s",
        datefmt="%Y-%m-%d %H:%M:%S",
    )

    has_stream = any(isinstance(handler, logging.StreamHandler) for handler in logger.handlers)
    has_file = any(isinstance(handler, logging.FileHandler) for handler in logger.handlers)

    if not has_stream:
        stream_handler = logging.StreamHandler()
        stream_handler.setFormatter(formatter)
        logger.addHandler(stream_handler)

    if not has_file:
        file_handler = logging.FileHandler(logs_dir / "scraper.log", encoding="utf-8")
        file_handler.setFormatter(formatter)
        logger.addHandler(file_handler)

    if log_queue is not None and event_loop is not None:
        has_async_queue = any(isinstance(handler, AsyncQueueHandler) for handler in logger.handlers)
        if not has_async_queue:
            queue_handler = AsyncQueueHandler(log_queue, event_loop)
            queue_handler.setFormatter(formatter)
            logger.addHandler(queue_handler)

    return logger
