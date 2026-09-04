"""Attachment selector matching.

Playwright's `[attr*='X']` is plain substring containment on the attribute
string, so these selectors can be checked without a browser: a selector
"matches" an href iff the href contains that substring.

Found during a live scrape: "/student/profile" contains "file" as a bare
substring ("pro" + "file"), so a[href*='file'] treated the nav's profile link
as an attachment link on every task page, wasting a 5s click-and-wait-for-
download timeout per task (112 occurrences in one session's logs) before it
timed out and moved on.
"""

from __future__ import annotations

import re

from src.selectors import SELECTORS

# The real attachment link a successful download logged in this project.
REAL_ATTACHMENT_HREF = (
    "https://cdn.ca.managebac.com/uploads/term_report/file/13397827/"
    "Term_1_Report.pdf?Expires=1776014062&Signature=abc"
)

# Genuine ManageBac nav links that must never be treated as attachments.
NON_ATTACHMENT_HREFS = [
    "/student/profile",
    "/student/classes/12847088/files",  # the "Files" tab, not a file itself
    "/student/dashboard",
    "/student/settings/profile",
]


def _substring_selectors() -> list[str]:
    """The href*='...' selectors, with their substring extracted."""
    pattern = re.compile(r"href\*='([^']*)'")
    return [pattern.search(s).group(1) for s in SELECTORS.attachment if "*=" in s]


def matches_any(href: str) -> bool:
    """Would any attachment selector treat this href as an attachment link?

    Mirrors what Playwright's locator.all() would find: true if the href
    contains any of the substring selectors' target strings.
    """
    return any(substring in href for substring in _substring_selectors())


class TestAttachmentSelectorSubstrings:
    def test_real_attachment_link_still_matches(self):
        assert matches_any(REAL_ATTACHMENT_HREF) is True

    def test_profile_link_no_longer_matches(self):
        """The regression this file exists to pin: "file" alone matched
        "profile"; "/file/" as a path segment does not."""
        assert matches_any("/student/profile") is False

    def test_settings_profile_link_does_not_match(self):
        assert matches_any("/student/settings/profile") is False

    def test_no_selector_uses_a_bare_file_substring(self):
        """Guards against someone reintroducing a[href*='file'] later."""
        assert "file" not in _substring_selectors()
        assert "/file/" in _substring_selectors()

    def test_files_tab_link_is_not_treated_as_a_download(self):
        # ".../files" (a tab, plural, no trailing content) should not match
        # any selector: it isn't an attachment, attachment, or /file/ link.
        assert matches_any("/student/classes/12847088/files") is False


class TestDownloadedFalsePositive:
    def test_confirmed_managebac_url_shapes(self):
        """Every href this bug is known to affect, in one place."""
        for href in NON_ATTACHMENT_HREFS:
            assert not matches_any(href), f"{href!r} should not look like an attachment"
