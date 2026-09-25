"""Parse docs/ios/app-store-listing.md — the single reviewed source of what is typed into App
Store Connect. Shared by the listing lint (ios/tests/test_ios_gates.py) and the paste sheet /
read-only verifier (ios/tools/asc_listing.py), so the two can never read the doc differently.

Stdlib only.
"""
from __future__ import annotations

import re
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
LISTING = ROOT / "docs" / "ios" / "app-store-listing.md"

# App Store Connect's limits (characters). The lint enforces them; the sheet prints them.
LIMITS = {"name": 30, "subtitle": 30, "promo": 170, "description": 4000, "keywords": 100,
          "review_notes": 4000}


def section(text: str, heading_prefix: str) -> str:
    """Body of the first `## <heading_prefix>…` section, up to the next `## `."""
    m = re.search(rf"(?ms)^## {re.escape(heading_prefix)}[^\n]*\n(.*?)(?=^## |\Z)", text)
    return m.group(1) if m else ""


def subsection(text: str, heading_prefix: str) -> str:
    """Body of the first `### <heading_prefix>…` subsection, up to the next `## ` or `### `."""
    m = re.search(rf"(?ms)^### {re.escape(heading_prefix)}[^\n]*\n(.*?)(?=^##+ |\Z)", text)
    return m.group(1) if m else ""


def blockquote(body: str) -> str:
    """The `>` lines of a section, markers removed, joined with newlines (blank `>` = blank line)."""
    lines = [ln[1:].strip() for ln in body.splitlines() if ln.startswith(">")]
    return "\n".join(lines).strip()


def listing_url(text: str, label: str) -> str | None:
    """The "Submit this" URL of a `| <label> | `https://…` |` row, or None."""
    m = re.search(rf"(?m)^\| {re.escape(label)} \| `([^`]+)`", text)
    return m.group(1) if m else None


def _identity(text: str, label: str) -> str | None:
    """The value of an Identity-table row: the leading `backticked` value when the cell starts with
    one (prose may follow), else the leading words before any " (…" or " — …" commentary."""
    m = re.search(rf"(?m)^\| {re.escape(label)} \| ([^|]+)\|", text)
    if not m:
        return None
    cell = m.group(1).strip()
    tick = re.match(r"`([^`]+)`", cell)
    if tick:
        return tick.group(1)
    return re.split(r"\s+\(|\s+—\s+", cell)[0].strip()


def plain(md: str) -> str:
    """Markdown → the plain text App Store Connect takes: drop ** and backticks, re-flow
    hard-wrapped lines into one line per paragraph, keep blank lines and bullet/label lines."""
    text = md.replace("**", "").replace("`", "")
    out: list[str] = []
    for para in re.split(r"\n\s*\n", text.strip()):
        lines = [ln.strip() for ln in para.splitlines() if ln.strip()]
        if any(ln.startswith(("•", "- ")) for ln in lines[1:]):
            out.append("\n".join(lines))          # a list: one item per line
        else:
            out.append(" ".join(lines))           # prose: re-flow the hard wrap
    return "\n\n".join(out)


def load(path: Path = LISTING) -> dict:
    """Every field the App Store Connect console takes, as it must be pasted."""
    text = path.read_text(encoding="utf-8")
    review = section(text, "App Review Information")
    email = re.search(r"[\w.+-]+@[\w-]+\.[\w.]+", review)
    return {
        "name": _identity(text, "Name"),
        "subtitle": _identity(text, "Subtitle"),
        "primary_category": _identity(text, "Primary category"),
        "secondary_category": _identity(text, "Secondary category"),
        "copyright": _identity(text, "Copyright"),
        "keywords": re.search(r"`([^`]+)`", section(text, "Keywords")).group(1),
        "promo": plain(blockquote(section(text, "Promotional text"))),
        "description": plain(blockquote(section(text, "Description"))),
        "support_url": listing_url(text, "Support URL"),
        "marketing_url": listing_url(text, "Marketing URL"),
        "privacy_url": listing_url(text, "Privacy Policy URL"),
        "review_email": email.group(0) if email else None,
        "review_notes": plain(blockquote(subsection(review, "Review notes"))),
    }
