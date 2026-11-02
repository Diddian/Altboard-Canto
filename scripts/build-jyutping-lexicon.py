#!/usr/bin/env python3
"""Pin yuetyam/jyutping's CC0 source and compile an indexed offline SQLite lexicon.

Upstream includes a lexicon based on Rime-Cantonese. Preserve applicable attribution:
https://github.com/rime/rime-cantonese (CC-BY 4.0). This script deliberately uses
only jyutping.txt and does not bundle ODbL jyut6ping3.maps data.
"""
import argparse
import hashlib
import os
import pathlib
import re
import sqlite3
import urllib.request

REVISION = "16bda076094abd63e0961cdc49e2b08ab4e381a3"
GIT_BLOB_SHA1 = "708236a9458ec933aa3d2b70aa372e613a7cc0b6"
UPSTREAM_FILE = "Modules/Preparing/Sources/Preparing/Resources/jyutping.txt"
DOWNLOAD_URL = f"https://raw.githubusercontent.com/yuetyam/jyutping/{REVISION}/{UPSTREAM_FILE}"
VALID_ROMANIZATION = re.compile(r"^[a-z]+[1-6](?: [a-z]+[1-6])*$")


def yale_syllable(jyutping: str) -> str:
    """Unmarked Yale typing alias for a single Jyutping syllable."""
    plain = jyutping.rstrip("123456")
    if plain.startswith("j"):
        plain = "y" + plain[1:]
    elif plain.startswith("z"):
        plain = "j" + plain[1:]
    elif plain.startswith("c"):
        plain = "ch" + plain[1:]
    plain = plain.replace("oe", "eu").replace("eo", "eu")
    plain = plain.replace("aa", "a")
    return plain


def yale_spelling(jyutping: str) -> str:
    return "".join(yale_syllable(syl) for syl in jyutping.split())


def read_source(input_file: str | None) -> bytes:
    if input_file:
        return pathlib.Path(input_file).read_bytes()
    request = urllib.request.Request(DOWNLOAD_URL, headers={"User-Agent": "Altboard-Canto-builder"})
    with urllib.request.urlopen(request, timeout=60) as response:
        return response.read()

def compile_database(source: bytes, output: pathlib.Path, verify_upstream: bool) -> int:
    if verify_upstream:
        digest = hashlib.sha1(b"blob " + str(len(source)).encode() + b"\0" + source).hexdigest()
        if digest != GIT_BLOB_SHA1:
            raise ValueError(f"Upstream source hash mismatch: {digest} != {GIT_BLOB_SHA1}")
    output.parent.mkdir(parents=True, exist_ok=True)
    if output.exists():
        output.unlink()
    db = sqlite3.connect(str(output))
    try:
        db.execute("PRAGMA page_size = 4096")
        db.execute("PRAGMA journal_mode = DELETE")
        db.execute("PRAGMA synchronous = OFF")
        db.execute("""CREATE TABLE entries (
            word TEXT NOT NULL,
            romanization TEXT NOT NULL,
            plain TEXT NOT NULL,
            compact TEXT NOT NULL,
            yale TEXT NOT NULL,
            initials TEXT NOT NULL,
            priority INTEGER NOT NULL
        )""")
        batch = []
        seen = set()
        count = 0
        # Reviewed common Cantonese phrases rank before the upstream lexicon.
        # Keep the upstream bytes/hash unchanged and additions auditable.
        supplemental = pathlib.Path(__file__).with_name("cantonese-phrases.tsv")
        lines = supplemental.read_text(encoding="utf-8").splitlines() + source.decode("utf-8").splitlines()
        for raw in lines:
            fields = raw.strip().split("\t")
            if len(fields) != 2:
                continue
            word, romanization = fields
            romanization = " ".join(romanization.lower().split())
            if not word or len(word) > 30 or not VALID_ROMANIZATION.fullmatch(romanization):
                continue
            key = (word, romanization)
            if key in seen:
                continue
            seen.add(key)
            syllables = romanization.split(" ")
            plain = "".join(c for c in romanization if "a" <= c <= "z")
            compact = romanization.replace(" ", "")
            initials = "".join(s[0] for s in syllables)
            yale = yale_spelling(romanization)
            batch.append((word, romanization, plain, compact, yale, initials, count))
            count += 1
            if len(batch) >= 15000:
                db.executemany("INSERT INTO entries VALUES (?,?,?,?,?,?,?)", batch)
                batch.clear()
        if batch:
            db.executemany("INSERT INTO entries VALUES (?,?,?,?,?,?,?)", batch)
        if count < 10000 and verify_upstream:
            raise ValueError(f"Lexicon unexpectedly small: {count} entries")
        db.executescript("""
            CREATE INDEX idx_entries_word ON entries(word, priority);
            CREATE INDEX idx_entries_plain ON entries(plain, priority);
            CREATE INDEX idx_entries_compact ON entries(compact, priority);
            CREATE INDEX idx_entries_yale ON entries(yale, priority);
            CREATE INDEX idx_entries_initials ON entries(initials, priority);
        """)
        db.commit()
        db.execute("VACUUM")
        db.execute("PRAGMA optimize")
        db.commit()
        for word, romanization in [("你好", "nei5 hou2"), ("我", "ngo5"), ("食", "sik6"), ("今日", "gam1 jat6")]:
            found = db.execute("SELECT 1 FROM entries WHERE word=? AND romanization=? LIMIT 1", (word, romanization)).fetchone()
            if not found and verify_upstream:
                raise ValueError(f"Missing essential entry {word} ({romanization})")
        if verify_upstream:
            assert db.execute(
                "SELECT 1 FROM entries WHERE yale=? AND word='今日' LIMIT 1", ("gamyat",)
            ).fetchone(), "Yale gamyat must suggest 今日"
        print(f"Compiled {count} unique entries to {output} ({output.stat().st_size} bytes)")
        return count
    finally:
        db.close()

def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--input", help="Optional local fixture; upstream hash check is skipped")
    parser.add_argument("--output", default="JyutpingResources/jyutping.sqlite3")
    args = parser.parse_args()
    count = compile_database(read_source(args.input), pathlib.Path(args.output), verify_upstream=not bool(args.input))
    if not args.input and count < 10000:
        raise SystemExit("Incomplete lexicon")

if __name__ == "__main__":
    main()
