#!/usr/bin/env python3
"""Write the Hukamnama test fixtures from the bundled iOS corpus — never by hand.

  python3 ios/tools/hukamnama_fixture.py            # (re)write the fixtures
  python3 ios/tools/hukamnama_fixture.py --check    # exit 1 if they differ from the corpus

Outputs (ios/App/Tests/Fixtures/):
  hukamnama-entry.json  the read-API shape (GET /v1/hukamnama/<date>), used by unit + UI tests
  hukamnama.apns        the push payload; also the `xcrun simctl push` fixture:
                        xcrun simctl push booted org.sggs.app ios/App/Tests/Fixtures/hukamnama.apns

Every Gurmukhi character is copied from ios/Resources/sggs-ios.sqlite. `range_sha256` is computed
here, in Python, as sha256 of the range's NFC Gurmukhi lines joined by "\\n"; the Swift unit tests
recompute it from the app's corpus, so the two implementations must agree (a cross-language
golden). The shabad is a fixed, arbitrary composition (the first that opens on Ang 673); it is
NOT a claim about any day's actual Hukamnama.
"""
import hashlib
import json
import re
import sqlite3
import sys
import unicodedata
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
DB = ROOT / "ios" / "Resources" / "sggs-ios.sqlite"
MANIFEST = ROOT / "ios" / "Resources" / "sggs-ios.manifest.json"
OUT = ROOT / "ios" / "App" / "Tests" / "Fixtures"
ANG = 673
DATE = "2026-11-09"
DATE_LABEL = "Mon 9 Nov · Amritsar"


def range_sha256(lines):
    joined = "\n".join(unicodedata.normalize("NFC", g) for g in lines)
    return hashlib.sha256(joined.encode("utf-8")).hexdigest()


VERSE_END = re.compile(r"॥[੦-੯]+॥$")
RAHAO_MAX_LINES = 3


def rahao_block(rows):
    """The one ਰਹਾਉ couplet, by the service's rule (services/hukamnama corpus.rahao_block in
    sggs-platform): the rahao line plus the verse lines just before it, back to a numbered verse
    end or a heading, at most 3 lines; none when there is no rahao or several."""
    marked = [i for i, r in enumerate(rows) if r[5]]
    if len(marked) != 1:
        return []
    start = end = marked[0]
    while start > 0 and not rows[start - 1][2] and not VERSE_END.search(rows[start - 1][3]):
        start -= 1
    if end - start + 1 > RAHAO_MAX_LINES:
        return []
    return [r[3] for r in rows[start:end + 1]]


def build():
    con = sqlite3.connect(f"file:{DB}?mode=ro", uri=True)
    comp = con.execute(
        "SELECT comp_id FROM lines GROUP BY comp_id HAVING min(ang) = ? ORDER BY min(id) LIMIT 1", (ANG,)
    ).fetchone()[0]
    rows = con.execute(
        "SELECT id, ang, is_header, gurmukhi, translit, is_rahao FROM lines WHERE comp_id = ? ORDER BY id", (comp,)
    ).fetchall()
    ids = [r[0] for r in rows]
    assert ids == list(range(ids[0], ids[-1] + 1)), "the composition's ids are not contiguous"
    opening = next(r for r in rows if not r[2])
    scripture = json.loads(MANIFEST.read_text())["scripture_sha256"]
    rahao = rahao_block(rows)
    assert rahao, "the fixture shabad must carry a rahao couplet"
    entry = {
        "amritsar_date": DATE,
        "status": "published",
        "ang": opening[1],
        "first_line_id": ids[0],
        "last_line_id": ids[-1],
        "comp_id": comp,
        "opening_gurmukhi": opening[3],
        "opening_translit": opening[4],
        "rahao_gurmukhi": rahao,
        "range_sha256": range_sha256([r[3] for r in rows]),
        "scripture_sha256": scripture,
        "published_at": "2026-11-09T00:04:00Z",
        "expected_by": "2026-11-09T00:30:00Z",
    }
    apns = {
        "Simulator Target Bundle": "org.sggs.app",
        "aps": {
            "alert": {
                "title": "Hukamnama · Sri Harmandir Sahib",
                "subtitle": DATE_LABEL,
                "body": f"{opening[3]}\nSri Guru Granth Sahib Ji · Ang {opening[1]}",
            },
            "sound": "default",
            "interruption-level": "active",
            "thread-id": "hukamnama",
            "mutable-content": 1,
        },
        "url": f"sggs://hukamnama/{DATE}",
        "amritsar_date": DATE,
        "ang": opening[1],
        "first_line_id": ids[0],
        "last_line_id": ids[-1],
        "comp_id": comp,
        "range_sha256": entry["range_sha256"],
        "scripture_sha256": scripture,
        "opening_translit": opening[4],
        "rahao_gurmukhi": rahao,
    }
    dump = lambda o: json.dumps(o, ensure_ascii=False, indent=2, sort_keys=True) + "\n"
    return {"hukamnama-entry.json": dump(entry), "hukamnama.apns": dump(apns)}


def main():
    files = build()
    if "--check" in sys.argv:
        bad = [n for n, t in files.items() if not (OUT / n).exists() or (OUT / n).read_text(encoding="utf-8") != t]
        if bad:
            print("stale Hukamnama fixtures:", ", ".join(bad), "— run: python3 ios/tools/hukamnama_fixture.py")
            return 1
        print("Hukamnama fixtures match the corpus")
        return 0
    OUT.mkdir(parents=True, exist_ok=True)
    for n, t in files.items():
        (OUT / n).write_text(t, encoding="utf-8")
        print("wrote", OUT / n)
    return 0


if __name__ == "__main__":
    sys.exit(main())
