#!/usr/bin/env python3
"""Compile the public-domain Fcitx5 Cangjie, Quick and Stroke5 tables to SQLite.

Only table DATA are imported, not the GPL program. Source tables are pinned
to a repository revision and verified against their Git blob hashes.
"""
import argparse
import base64
import hashlib
import itertools
import json
import pathlib
import re
import sqlite3
import time
import urllib.request

REVISION = "dbc7154a7f0b9fc04313160ae8066ed4d8cbc446"
SOURCE = "fcitx/fcitx5-table-extra"
SOURCES = {
    "cangjie3": "5ae9f8e99e996933b24b4399b18b622259c5604e",
    "cangjie5": "35ede60198ae0556dbc6e2ca9f2aff8ab8526898",
    "quick3": "995fcb5b4a9409c077c2b8ff2548c249e89fa8c0",
    "quick5": "4859cdf17d17d9f94cf71f344684aa6fadafb747",
    "stroke5": "a0d3b924bd4a109d57ebd0dfd03dcf77c18c53f5",
}
ROOT = pathlib.Path(__file__).resolve().parent.parent
OUTPUT = ROOT / "JyutpingResources" / "chinese-shapes.sqlite3"
VALID_LETTERS = re.compile(r"^[a-z]{1,6}$")
VALID_STROKES = re.compile(r"^[nm,./]{1,5}$")
RIME_STROKE_REVISION = "1e8fff9b9494ddec23b0cbc526bcfd8171a6fd48"
RIME_STROKE_BLOB = "5a4a49a825d40d85709b197caade546f192a5bde"
RIME_CODE = re.compile(r"^[hspnz]{1,64}$")
STROKE_TRANSLATION = str.maketrans("hspnz", "m/,.n")
# These canonical characters are *internal*; the UI shows stroke glyphs.
STROKE_ALPHABET = "m/,.n"


def github_blob_sha(data: bytes) -> str:
    return hashlib.sha1(b"blob " + str(len(data)).encode() + b"\0" + data).hexdigest()


def download(name: str, *, source_directory: pathlib.Path | None = None) -> bytes:
    if source_directory is None:
        raise ValueError("A local, pinned table directory is required")
    data = (source_directory / f"{name}.txt").read_bytes()
    digest = github_blob_sha(data)
    if digest != SOURCES[name]:
        raise ValueError(f"{name}: upstream Git blob mismatch {digest}")
    return data


def parse_table(data: bytes, name: str):
    """Preserve source order within each code, but deduplicate duplicate rows."""
    started = False
    regex = VALID_STROKES if name == "stroke5" else VALID_LETTERS
    seen = set()
    for order, raw in enumerate(data.decode("utf-8-sig").splitlines()):
        line = raw.strip()
        if line.lower() in ("[data]", "[数据]"):
            started = True
            continue
        if not started or not line or line.startswith(("#", ";", "&")):
            continue
        parts = line.split(None, 1)
        if len(parts) != 2:
            continue
        code, word = parts
        word = word.strip()
        if not regex.fullmatch(code) or not 1 <= len(word) <= 8:
            continue
        if name.startswith("quick") and len(code) > 2:
            continue
        key = (code, word)
        if key in seen:
            continue
        seen.add(key)
        yield code, word, order


def parse_rime_stroke(data: bytes):
    """Normalize full Rime hspnz sequences into the existing five stroke keys.

    Keep the entire sequence; Fcitx5's short codes must not truncate it.
    A distinct normalized sequence is a valid alternative writing order.
    """
    started = False
    seen = set()
    for order, line in enumerate(data.decode("utf-8-sig").splitlines()):
        if line.strip() == "...":
            started = True
            continue
        if not started or not line or line.startswith("#"):
            continue
        fields = line.split("\t")
        if len(fields) < 2:
            continue
        word, original_code = fields[:2]
        if not word or len(word) > 8 or not RIME_CODE.fullmatch(original_code):
            continue
        code = original_code.translate(STROKE_TRANSLATION)
        if (code, word) in seen:
            continue
        seen.add((code, word))
        yield code, word, order


def download_rime_stroke(path: pathlib.Path | None = None) -> bytes:
    """Use pinned upstream bytes, never an unverified floating dictionary."""
    if path is not None:
        data = path.read_bytes()
    else:
        urls = [
            f"https://raw.githubusercontent.com/rime/rime-stroke/{RIME_STROKE_REVISION}/stroke.dict.yaml",
            ("https://api.github.com/repos/rime/rime-stroke/git/blobs/"
             f"{RIME_STROKE_BLOB}"),
        ]
        last_error = None
        for attempt in range(6):
            url = urls[attempt % len(urls)]
            try:
                request = urllib.request.Request(
                    url, headers={"User-Agent": "Altboard-Canto-dictionary-builder",
                                  "Accept": "application/vnd.github+json"}
                )
                with urllib.request.urlopen(request, timeout=60) as response:
                    data = response.read()
                if "api.github.com" in url:
                    response_data = json.loads(data)
                    data = base64.b64decode(response_data["content"])
                if github_blob_sha(data) != RIME_STROKE_BLOB:
                    raise ValueError("Rime Stroke source hash mismatch")
                break
            except (OSError, ValueError, KeyError) as error:
                last_error = error
                if attempt < 5:
                    time.sleep(min(2 ** attempt, 8))
        else:
            raise RuntimeError("Could not obtain pinned Rime Stroke data") from last_error
    digest = github_blob_sha(data)
    if digest != RIME_STROKE_BLOB:
        raise ValueError(f"Rime Stroke upstream Git blob mismatch: {digest}")
    return data


def load_cantonese_priority(path: pathlib.Path) -> dict[str, int]:
    if not path.is_file():
        return {}
    conn = sqlite3.connect(str(path))
    try:
        return dict(conn.execute(
            "SELECT word, MIN(priority) FROM entries GROUP BY word"
        ))
    finally:
        conn.close()


def compile_database(directory: pathlib.Path | None, output: pathlib.Path,
                     jyutping: pathlib.Path,
                     rime_source: bytes | None = None) -> dict[str, int]:
    frequencies = load_cantonese_priority(jyutping)
    output.parent.mkdir(parents=True, exist_ok=True)
    if output.exists():
        output.unlink()
    conn = sqlite3.connect(str(output))
    totals: dict[str, int] = {}
    try:
        conn.execute("PRAGMA journal_mode=OFF")
        conn.execute("PRAGMA synchronous=OFF")
        conn.execute("""CREATE TABLE entries (
            method TEXT NOT NULL,
            variant INTEGER NOT NULL,
            code TEXT NOT NULL,
            word TEXT NOT NULL,
            priority INTEGER NOT NULL,
            source_order INTEGER NOT NULL,
            source TEXT NOT NULL
        )""")
        for name in SOURCES:
            mode = "stroke" if name == "stroke5" else (
                "quick" if name.startswith("quick") else "cangjie"
            )
            variant = 0 if mode == "stroke" else int(name[-1])
            rows = []
            for code, word, order in parse_table(
                    download(name, source_directory=directory), name):
                # Canto phrase frequencies help HK everyday glyphs appear
                # before rare extension characters in the merged tables.
                known = frequencies.get(word)
                cjk_common = all(
                    "\u3400" <= char <= "\u9fff" or char in "，。？！"
                    for char in word
                )
                priority = (0 if known is not None else 1) * 1_000_000_000
                priority += min(known or 900_000, 900_000) * 100
                priority += 0 if cjk_common else 1_000_000
                priority += min(order, 999_999)
                rows.append((mode, variant, code, word, priority, order, name))
            if len(rows) < 3000:
                raise ValueError(f"{name}: unexpectedly small {len(rows)}")
            conn.executemany("INSERT INTO entries VALUES (?,?,?,?,?,?,?)", rows)
            totals[name] = len(rows)

        rime_data = download_rime_stroke() if rime_source is None else rime_source
        # Even locally supplied bytes must match the exact upstream dictionary.
        if github_blob_sha(rime_data) != RIME_STROKE_BLOB:
            raise ValueError("Rime Stroke source did not match the pinned Git blob")
        rime_rows = []
        for code, word, order in parse_rime_stroke(rime_data):
            known = frequencies.get(word)
            cjk_common = all("\u3400" <= char <= "\u9fff" for char in word)
            priority = (0 if known is not None else 1) * 1_000_000_000
            priority += min(known or 900_000, 900_000) * 100
            priority += 0 if cjk_common else 1_000_000
            priority += min(order, 999_999)
            rime_rows.append(("stroke", 0, code, word, priority, order, "rime-stroke"))
        if len(rime_rows) < 3000:
            raise ValueError(f"rime-stroke: unexpectedly small {len(rime_rows)}")
        conn.executemany("INSERT INTO entries VALUES (?,?,?,?,?,?,?)", rime_rows)
        totals["rime-stroke"] = len(rime_rows)

        conn.executescript("""
            CREATE INDEX idx_table_code ON entries(method, code, priority);
            CREATE TABLE stroke_prefix (
                prefix TEXT NOT NULL,
                word TEXT NOT NULL,
                code TEXT NOT NULL,
                priority INTEGER NOT NULL
            );
        """)
        # Precompute only short prefixes, where scanning the full Rime table
        # on every iPhone key-down would be needlessly expensive.
        prefix_rows = []
        for size in (1, 2, 3):
            for strokes in itertools.product(STROKE_ALPHABET, repeat=size):
                prefix = "".join(strokes)
                matches = conn.execute(
                    """SELECT word,code,MIN(priority) AS rank
                       FROM entries
                       WHERE method='stroke' AND code>=? AND code<? AND code!=?
                       GROUP BY word ORDER BY rank,word LIMIT 240""",
                    (prefix, prefix + "\U0010ffff", prefix)
                )
                prefix_rows.extend((prefix, word, code, priority)
                                   for word, code, priority in matches)
        conn.executemany("INSERT INTO stroke_prefix VALUES (?,?,?,?)", prefix_rows)
        conn.executescript("""
            CREATE INDEX idx_stroke_prefix_rank ON stroke_prefix(prefix, priority);
        """)
        conn.commit()
        conn.execute("VACUUM")
        conn.commit()
        for method, key in [("quick", "aa"), ("cangjie", "a"), ("stroke", "m")]:
            if not conn.execute("SELECT 1 FROM entries WHERE method=? AND code=? LIMIT 1",
                                (method, key)).fetchone():
                raise ValueError(f"{method}: essential code {key!r} missing")
        if not all(conn.execute(
            "SELECT 1 FROM entries WHERE method=? AND variant=? LIMIT 1",
            (method, variant)
        ).fetchone() for method in ("quick", "cangjie") for variant in (3, 5)):
            raise ValueError("Both Cangjie and Quick generations are required")
        print("Chinese shape tables:", totals, "output bytes:", output.stat().st_size)
        return totals
    finally:
        conn.close()


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--source-dir", type=pathlib.Path,
                        default=ROOT / "scripts" / "data" / "chinese-shapes",
                        help="Pinned public-domain Fcitx5 table data")
    parser.add_argument("--output", type=pathlib.Path, default=OUTPUT)
    parser.add_argument("--jyutping-db", type=pathlib.Path,
                        default=ROOT / "JyutpingResources" / "jyutping.sqlite3")
    parser.add_argument("--rime-stroke-source", type=pathlib.Path,
                        help="Optional local copy of pinned Rime stroke.dict.yaml")
    args = parser.parse_args()
    rime_data = (download_rime_stroke(args.rime_stroke_source)
                 if args.rime_stroke_source else None)
    compile_database(args.source_dir, args.output, args.jyutping_db,
                     rime_source=rime_data)


if __name__ == "__main__":
    main()
