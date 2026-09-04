"""Pull MYP assessment criteria out of task text.

ManageBac does not expose criteria as structured data anywhere the scraper can
currently reach, so they are read from the task brief itself. Real briefs in
this repo write them as "Criterion B: Investigating", and shorter forms like
"Criteria A and B" are common too.

Text-derived rather than DOM-derived on purpose: the scraper already has this
text, whereas selectors for an assignment page could not be verified without a
live summative task to inspect, and unverified selectors are what caused the
past scrape failure recorded in data/debug_zero_tasks.png.
"""

from __future__ import annotations

import re
from typing import Any, Iterable

#: MYP uses criteria A-D. Anything past D is far more likely to be a false
#: positive (a list item, a figure label) than a real criterion.
VALID_LETTERS = ("A", "B", "C", "D")

#: "Criterion B: Investigating" - a letter with a name after the colon.
#:
#: The name is lazy and stops at the next criterion, so a run-on sentence like
#: "Criterion B: Investigating and Criterion C: Communicating" does not let the
#: first name swallow the second. A bare "and" is not a terminator, because
#: names such as "Knowing and understanding" contain one.
_NAMED = re.compile(
    r"criteri(?:on|a)\s*([A-D])\b\s*[:–—-]\s*"
    r"(.{2,60}?)"
    r"(?=[\n\r;.]|\s*,?\s*(?:and\s+)?criteri(?:on|a)\b|$)",
    re.IGNORECASE,
)

#: "Criteria A and B", "Criterion A, B & C", "Criteria: A, C" - letters only.
_BARE = re.compile(
    r"criteri(?:on|a)\s*:?\s*((?:[A-D]\s*(?:,|and|&|\+)\s*)*[A-D])\b",
    re.IGNORECASE,
)

_LETTER = re.compile(r"\b([A-D])\b")

#: Trailing fragments that are punctuation or list scaffolding, not a name.
_NAME_TRAILING = re.compile(r"(?:\s+and)?[\s:,\-–—]+$", re.IGNORECASE)


def _clean_name(raw: str) -> str:
    name = _NAME_TRAILING.sub("", raw.strip())
    name = re.sub(r"\s+", " ", name)
    return name


def extract_criteria(*texts: str | None) -> list[dict[str, Any]]:
    """Return criteria found across the given texts, ordered A-D.

    Each entry is ``{"letter": "B", "name": "Investigating"}``; ``name`` is
    None when the text only listed the letter. Later texts enrich earlier ones:
    a bare "Criteria A and B" plus a named "Criterion B: Investigating"
    resolves to B carrying its name.
    """
    found: dict[str, str | None] = {}

    def record(letter: str, name: str | None) -> None:
        letter = letter.upper()
        if letter not in VALID_LETTERS:
            return
        # Never let a bare mention erase a name discovered elsewhere.
        if found.get(letter) is None:
            found[letter] = name
        elif name:
            found[letter] = found[letter] or name

    for text in texts:
        if not text:
            continue

        for letter, raw_name in _NAMED.findall(text):
            name = _clean_name(raw_name)
            record(letter, name or None)

        for group in _BARE.findall(text):
            for letter in _LETTER.findall(group):
                record(letter, None)

    return [
        {"letter": letter, "name": found[letter]}
        for letter in VALID_LETTERS
        if letter in found
    ]


def merge_criteria(
    existing: Iterable[dict[str, Any]] | None,
    incoming: Iterable[dict[str, Any]] | None,
) -> list[dict[str, Any]]:
    """Combine two criteria lists, preferring whichever supplies a name."""
    merged: dict[str, str | None] = {}

    for source in (existing or (), incoming or ()):
        for entry in source:
            if not isinstance(entry, dict):
                continue
            letter = str(entry.get("letter", "")).upper()
            if letter not in VALID_LETTERS:
                continue
            name = entry.get("name") or None
            merged[letter] = merged.get(letter) or name

    return [
        {"letter": letter, "name": merged[letter]}
        for letter in VALID_LETTERS
        if letter in merged
    ]
