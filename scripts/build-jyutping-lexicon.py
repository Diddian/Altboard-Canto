#!/usr/bin/env python3
"""Pin yuetyam/jyutping's CC0 source and compile an indexed offline SQLite lexicon.

Upstream includes a lexicon based on Rime-Cantonese. Preserve applicable attribution:
https://github.com/rime/rime-cantonese (CC-BY 4.0). This script deliberately uses
only jyutping.txt and does not bundle ODbL jyut6ping3.maps data.
"""
import argparse
import base64
import hashlib
import itertools
import json
import os
import pathlib
import re
import sqlite3
import time
import urllib.request

REVISION = "16bda076094abd63e0961cdc49e2b08ab4e381a3"
GIT_BLOB_SHA1 = "708236a9458ec933aa3d2b70aa372e613a7cc0b6"
UPSTREAM_FILE = "Modules/Preparing/Sources/Preparing/Resources/jyutping.txt"
DOWNLOAD_URL = f"https://raw.githubusercontent.com/yuetyam/jyutping/{REVISION}/{UPSTREAM_FILE}"
VALID_ROMANIZATION = re.compile(r"^[a-z]+[1-6](?: [a-z]+[1-6])*$")


def yale_syllable(jyutping: str) -> str:
    """Unmarked Yale typing alias for a single Jyutping syllable."""
    plain = jyutping.rstrip("123456")
    # jy- is one Jyutping onset; converting j->y must not yield yyu/yyun.
    if plain.startswith("jy"):
        plain = "y" + plain[2:]
    elif plain.startswith("j"):
        plain = "y" + plain[1:]
    elif plain.startswith("z"):
        plain = "j" + plain[1:]
    elif plain.startswith("c"):
        plain = "ch" + plain[1:]
    plain = plain.replace("oe", "eu").replace("eo", "eu")
    # Both Yale and Sidney Lau distinguish long aa from short a.
    # Removing the second a erased chaan (殘) and other valid spellings.
    return plain


def yale_spelling(jyutping: str) -> str:
    return "".join(yale_syllable(syl) for syl in jyutping.split())


def sidney_lau_syllable(jyutping: str) -> str:
    """Unmarked Sidney Lau typing alias derived from canonical Jyutping."""
    yale = yale_syllable(jyutping)
    # Convert only complete syllable finals. 'jeung' has -eung, NOT -eun:
    # the previous global replacement incorrectly produced 'jung'.
    if yale in ("yu", "yun", "yut"):
        return {"yu": "yue", "yun": "yuen", "yut": "yuet"}[yale]
    for old, new in (
        ("eui", "ui"), ("eun", "un"), ("eut", "ut"),
        ("yun", "uen"), ("yut", "uet"), ("yu", "ue"), ("ou", "o"),
    ):
        if yale.endswith(old):
            return yale[:-len(old)] + new
    return yale


def sidney_lau_spelling(jyutping: str) -> str:
    return "".join(sidney_lau_syllable(syl) for syl in jyutping.split())


def mixed_phrase_aliases(word: str, romanization: str) -> list[str]:
    """Indexed cross-scheme aliases for reviewed phrases, not the upstream corpus.

    Limit mixed spellings to at most two variant syllables. This keeps search
    bounded and avoids inventing arbitrary Cantonese homophones.
    """
    syllables = romanization.split()
    if len(syllables) < 2:
        return []
    choices = []
    for syllable in syllables:
        variants = [syllable.rstrip("123456"), yale_syllable(syllable),
                    sidney_lau_syllable(syllable)]
        choices.append(list(dict.fromkeys(variants)))
    canonical = "".join(s[0] for s in choices)
    uniform = {
        canonical, yale_spelling(romanization), sidney_lau_spelling(romanization)
    }
    result = []
    seen = set()
    for parts in itertools.product(*choices):
        changes = sum(a != b for a, b in zip(parts, (c[0] for c in choices)))
        if changes > 2:
            continue
        alias = "".join(parts)
        if alias not in uniform and alias not in seen:
            seen.add(alias)
            result.append(alias)
        if word.startswith("唔") and syllables[0] == "m4":
            colloquial = "ng" + "".join(parts[1:])
            if colloquial not in seen:
                seen.add(colloquial)
                result.append(colloquial)
        if len(result) >= 128:
            break
    return result


def negative_particle_aliases(word: str, romanization: str) -> list[str]:
    """Index colloquial ng for 唔 (m4) at any syllable boundary.

    Match the actual 唔 character and its m4 reading. Do not rewrite ng
    inside unrelated syllables such as ngaan or the English word long.
    These aliases cover the entire pinned lexicon, not just manual phrases.
    """
    syllables = romanization.split()
    if len(word) != len(syllables):
        return []
    positions = [i for i, (character, syllable) in enumerate(zip(word, syllables))
                 if character == "唔" and syllable == "m4"]
    if not positions:
        return []
    # Every 唔 position is supported. Enumerate mixed m/ng masks for
    # ordinary phrases; for long unusual phrases cover each position
    # individually and the all-ng spelling, without 2**n expansion.
    from itertools import combinations
    if len(positions) <= 5:
        subsets = [
            subset
            for count in range(1, len(positions) + 1)
            for subset in combinations(positions, count)
        ]
    else:
        subsets = [(position,) for position in positions]
        subsets.append(tuple(positions))
    seen = set()
    aliases = []
    for spell in (
        lambda syl: syl.rstrip("123456"),
        yale_syllable, sidney_lau_syllable,
    ):
        parts = [spell(syl) for syl in syllables]
        for subset in subsets:
            rewritten = parts.copy()
            for position in subset:
                rewritten[position] = "ng"
            alias = "".join(rewritten)
            if alias not in seen:
                seen.add(alias)
                aliases.append(alias)
    return aliases


def read_source(input_file: str | None) -> bytes:
    if input_file:
        return pathlib.Path(input_file).read_bytes()
    urls = [
        DOWNLOAD_URL,
        f"https://api.github.com/repos/yuetyam/jyutping/contents/{UPSTREAM_FILE}?ref={REVISION}",
    ]
    last_error: OSError | None = None
    for attempt in range(5):
        url = urls[attempt % 2]
        try:
            request = urllib.request.Request(
                url, headers={"User-Agent": "Altboard-Canto-builder"}
            )
            with urllib.request.urlopen(request, timeout=60) as response:
                data = response.read()
            if "api.github.com" in url:
                data = base64.b64decode(json.loads(data)["content"])
            return data
        except (OSError, ValueError, KeyError) as error:
            last_error = error
            if attempt < 4:
                time.sleep(min(2 ** attempt, 8))
    raise RuntimeError("Could not obtain verified pinned Cantonese lexicon") from last_error

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
            sidney TEXT NOT NULL,
            initials TEXT NOT NULL,
            priority INTEGER NOT NULL
        )""")
        batch = []
        mixed_batch = []
        seen = set()
        seen_aliases = set()
        count = 0
        # Reviewed common Cantonese phrases rank before the upstream lexicon.
        # Keep the upstream bytes/hash unchanged and additions auditable.
        supplemental = pathlib.Path(__file__).with_name("cantonese-phrases.tsv")
        reviewed = supplemental.read_text(encoding="utf-8").splitlines()
        lines = reviewed + source.decode("utf-8").splitlines()
        db.execute("""CREATE TABLE mixed_aliases (
            alias TEXT NOT NULL,
            word TEXT NOT NULL,
            romanization TEXT NOT NULL,
            priority INTEGER NOT NULL
        )""")
        for line_number, raw in enumerate(lines):
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
            sidney = sidney_lau_spelling(romanization)
            batch.append((word, romanization, plain, compact, yale, sidney, initials, count))
            aliases = negative_particle_aliases(word, romanization)
            if line_number < len(reviewed):
                aliases.extend(mixed_phrase_aliases(word, romanization))
            for alias in aliases:
                key_alias = (alias, word)
                if key_alias not in seen_aliases:
                    seen_aliases.add(key_alias)
                    mixed_batch.append((alias, word, romanization, count))
            count += 1
            if len(batch) >= 15000:
                db.executemany("INSERT INTO entries VALUES (?,?,?,?,?,?,?,?)", batch)
                batch.clear()
        if batch:
            db.executemany("INSERT INTO entries VALUES (?,?,?,?,?,?,?,?)", batch)
        if mixed_batch:
            db.executemany("INSERT INTO mixed_aliases VALUES (?,?,?,?)", mixed_batch)
        if count < 10000 and verify_upstream:
            raise ValueError(f"Lexicon unexpectedly small: {count} entries")
        db.executescript("""
            CREATE INDEX idx_entries_word ON entries(word, priority);
            CREATE INDEX idx_entries_plain ON entries(plain, priority);
            CREATE INDEX idx_entries_compact ON entries(compact, priority);
            CREATE INDEX idx_entries_yale ON entries(yale, priority);
            CREATE INDEX idx_entries_sidney ON entries(sidney, priority);
            CREATE INDEX idx_entries_initials ON entries(initials, priority);
            CREATE INDEX idx_mixed_alias ON mixed_aliases(alias, priority);
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
            assert db.execute(
                "SELECT 1 FROM entries WHERE sidney=? AND word='今日' LIMIT 1", ("gamyat",)
            ).fetchone(), "Sidney Lau gamyat must suggest 今日"
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
