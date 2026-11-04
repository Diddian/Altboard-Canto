#!/usr/bin/env python3
"""Generate deterministic HKCanCor aggregate counts inside the offline Jyutping DB."""
import argparse
from collections import Counter
from concurrent.futures import ThreadPoolExecutor
import hashlib
import json
from pathlib import Path
import sqlite3
import time
from urllib.request import Request, urlopen

CORPUS_REVISION = "3d729c01e53f6056cb1c6c527953837e9a106147"
CORPUS_DIRECTORY = "src/pycantonese/data/hkcancor"
CORPUS_REPO = "jacksonllee/pycantonese"
MINIMUM_SOURCE_FILES = 58


def _request(url: str) -> bytes:
    error = None
    for attempt in range(3):
        try:
            with urlopen(Request(url, headers={"User-Agent": "Altboard-Canto-builder"}), timeout=50) as response:
                return response.read()
        except OSError as exc:
            error = exc
            time.sleep(attempt + 1)
    raise RuntimeError(f"Cannot retrieve pinned HKCanCor source: {url}") from error


def pinned_sources() -> list[tuple[str, bytes]]:
    listing = json.loads(_request(
        f"https://api.github.com/repos/{CORPUS_REPO}/contents/{CORPUS_DIRECTORY}"
        f"?ref={CORPUS_REVISION}"
    ))
    names = sorted(item["name"] for item in listing if item["name"].endswith(".cha"))
    if len(names) != MINIMUM_SOURCE_FILES:
        raise ValueError(f"Expected {MINIMUM_SOURCE_FILES} CHAT files, found {len(names)}")

    def fetch(name: str) -> tuple[str, bytes]:
        url = (f"https://raw.githubusercontent.com/{CORPUS_REPO}/{CORPUS_REVISION}/"
               f"{CORPUS_DIRECTORY}/{name}")
        return name, _request(url)

    with ThreadPoolExecutor(max_workers=8) as pool:
        return list(pool.map(fetch, names))


def _is_han(character: str) -> bool:
    code = ord(character)
    return 0x3400 <= code <= 0x9FFF or 0x20000 <= code <= 0x323AF


def utterances(chat: str):
    """Read speaker turns only, including wrapped lines; skip annotation tiers."""
    parts: list[str] = []
    for line in chat.splitlines():
        if line.startswith("*") and ":" in line:
            if parts:
                yield " ".join(parts)
            parts = [line.split(":", 1)[1].strip()]
        elif line.startswith("\t") and parts:
            parts.append(line.strip())
        elif parts:
            yield " ".join(parts)
            parts = []
    if parts:
        yield " ".join(parts)


def aggregate(sources: list[tuple[str, bytes]]):
    words: Counter[str] = Counter()
    grams: Counter[str] = Counter()
    turns = 0
    for _, data in sorted(sources):
        for sentence in utterances(data.decode("utf-8-sig")):
            turns += 1
            run: list[str] = []

            def flush() -> None:
                if not run:
                    return
                chars = "".join(run)
                for size in (1, 2, 3):
                    grams.update(chars[pos:pos + size] for pos in range(len(chars) - size + 1))
                run.clear()

            for token in sentence.split():
                if token and all(_is_han(char) for char in token):
                    if len(token) <= 12:
                        words[token] += 1
                    run.append(token)
                else:
                    flush()
            flush()
    return words, grams, turns


def install_counts(database: Path, sources: list[tuple[str, bytes]], production: bool = False) -> dict:
    words, grams, turns = aggregate(sources)
    if not words or not grams or not turns:
        raise ValueError("No Cantonese corpus material found")
    if production and (turns < 1000 or len(grams) < 2000):
        raise ValueError("Pinned HKCanCor download appears incomplete")
    if not database.exists():
        raise FileNotFoundError(database)
    db = sqlite3.connect(database)
    try:
        db.execute("PRAGMA journal_mode=DELETE")
        if not db.execute("SELECT 1 FROM sqlite_master WHERE name='entries'").fetchone():
            raise ValueError("The Jyutping lexicon must be generated first")
        with db:
            db.executescript("""
                DROP TABLE IF EXISTS corpus_words;
                DROP TABLE IF EXISTS corpus_ngrams;
                CREATE TABLE corpus_words (
                    word TEXT PRIMARY KEY NOT NULL,
                    frequency INTEGER NOT NULL
                ) WITHOUT ROWID;
                CREATE TABLE corpus_ngrams (
                    gram TEXT PRIMARY KEY NOT NULL,
                    frequency INTEGER NOT NULL
                ) WITHOUT ROWID;
            """)
            db.executemany("INSERT INTO corpus_words VALUES (?,?)", sorted(words.items()))
            db.executemany("INSERT INTO corpus_ngrams VALUES (?,?)", sorted(grams.items()))
        db.execute("VACUUM")
        db.execute("PRAGMA optimize")
        db.commit()
        if db.execute("PRAGMA quick_check").fetchone() != ("ok",):
            raise RuntimeError("N-gram SQLite integrity check failed")
    finally:
        db.close()
    checksum = hashlib.sha256()
    for prefix, entries in (("W", words), ("G", grams)):
        for key, count in sorted(entries.items()):
            checksum.update(f"{prefix}\t{key}\t{count}\n".encode("utf-8"))
    return {"turns": turns, "words": len(words), "ngrams": len(grams), "sha256": checksum.hexdigest()}


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--database", default="JyutpingResources/jyutping.sqlite3")
    parser.add_argument("--input-dir", type=Path, help="Local CHAT fixtures; never distributed")
    args = parser.parse_args()
    if args.input_dir:
        files = sorted(args.input_dir.glob("*.cha"))
        sources = [(file.name, file.read_bytes()) for file in files]
    else:
        sources = pinned_sources()
    result = install_counts(Path(args.database), sources, production=not bool(args.input_dir))
    print("HKCanCor aggregate model:", json.dumps(result, sort_keys=True))


if __name__ == "__main__":
    main()
