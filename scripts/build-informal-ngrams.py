#!/usr/bin/env python3
"""Install reviewed informal-language seed patterns beside corpus counts.

These short editorial examples are NOT corpus observations or usage frequencies.
Original HKCanCor statistics remain untouched in corpus_words/corpus_ngrams.
"""
from collections import Counter
from pathlib import Path
import re
import sqlite3
import sys

HERE = Path(__file__).resolve().parent
TOKENS = re.compile(r"[^\W_]+(?:['’][^\W_]+)*", re.UNICODE)
LANGUAGES = {"en", "de", "yue"}
EXAMPLE_LANGUAGES = {"en", "de", "yue", "en-mixed", "de-mixed"}
KINDS = {"slang", "short", "colloquial"}


def rows(path: Path, columns: int):
    for number, line in enumerate(path.read_text(encoding="utf-8").splitlines(), 1):
        if not line.strip() or line.startswith("#"):
            continue
        fields = [value.strip() for value in line.split("\t")]
        if len(fields) != columns or any(not field for field in fields):
            raise ValueError(f"{path.name}:{number}: expected {columns} TSV columns")
        yield fields


def normalize(term: str) -> str:
    return term.casefold().rstrip(".")


def is_han(char: str) -> bool:
    value = ord(char)
    return 0x3400 <= value <= 0x9FFF or 0x20000 <= value <= 0x323AF


def collect(directory: Path = HERE):
    terms = {}
    for language, display, kind in rows(directory / "informal-terms.tsv", 3):
        if language not in LANGUAGES or kind not in KINDS or len(display) > 32:
            raise ValueError(f"Invalid curated term: {language} {display}")
        key = normalize(display)
        if not key or not TOKENS.fullmatch(key):
            raise ValueError(f"Invalid curated key: {display}")
        identity = (language, key)
        if identity in terms:
            raise ValueError(f"Duplicate curated term: {identity}")
        terms[identity] = (display, kind)

    latin = Counter()
    chars = Counter()
    words = Counter()
    continuations = Counter()
    for language, sample in rows(directory / "informal-patterns.tsv", 2):
        if language not in EXAMPLE_LANGUAGES or len(sample) > 120:
            raise ValueError(f"Invalid curated example: {language} {sample}")
        tokens = [normalize(token) for token in TOKENS.findall(sample)]
        if not tokens:
            raise ValueError(f"Empty curated example: {sample}")
        if language == "yue":
            if any(not all(is_han(c) for c in token) for token in tokens):
                raise ValueError(f"Cantonese examples require Han tokens: {sample}")
            for token in tokens:
                if 1 <= len(token) <= 12:
                    words[token] += 1
            for previous, following in zip(tokens, tokens[1:]):
                if 1 <= len(following) <= 10:
                    for size in (1, 2):
                        continuations[(previous[-size:], following)] += 1
            text = "".join(tokens)
            for width in (1, 2, 3):
                chars.update(text[i:i+width] for i in range(len(text) - width + 1))
            continue
        actual = language.split("-", 1)[0]
        for i, token in enumerate(tokens):
            for width in (1, 2):
                if i >= width:
                    history = " ".join(tokens[i-width:i])
                    latin[(actual, history, token)] += 1
    if len(terms) < 15 or not latin or not chars:
        raise ValueError("Curated seed files are unexpectedly small")
    return terms, latin, words, chars, continuations


def install(database: Path, directory: Path = HERE) -> dict[str, int]:
    terms, latin, words, chars, continuations = collect(directory)
    if not database.is_file():
        raise FileNotFoundError(database)
    db = sqlite3.connect(database)
    try:
        if not db.execute("SELECT 1 FROM sqlite_master WHERE name='entries'").fetchone():
            raise ValueError("Generate the canonical Jyutping lexicon first")
        with db:
            db.executescript("""
                DROP TABLE IF EXISTS informal_terms;
                DROP TABLE IF EXISTS informal_ngrams;
                DROP TABLE IF EXISTS curated_cantonese_words;
                DROP TABLE IF EXISTS curated_cantonese_ngrams;
                CREATE TABLE informal_terms (
                    language TEXT NOT NULL, key TEXT NOT NULL,
                    display TEXT NOT NULL, kind TEXT NOT NULL,
                    PRIMARY KEY (language, key)
                ) WITHOUT ROWID;
                CREATE TABLE informal_ngrams (
                    language TEXT NOT NULL, history TEXT NOT NULL,
                    token TEXT NOT NULL, seed_weight INTEGER NOT NULL,
                    PRIMARY KEY (language, history, token)
                ) WITHOUT ROWID;
                CREATE INDEX idx_informal_ngrams_rank
                    ON informal_ngrams(language, history, seed_weight DESC, token);
                CREATE TABLE curated_cantonese_words (
                    word TEXT PRIMARY KEY NOT NULL,
                    seed_weight INTEGER NOT NULL
                ) WITHOUT ROWID;
                DROP TABLE IF EXISTS curated_cantonese_next;
                CREATE TABLE curated_cantonese_ngrams (
                    gram TEXT PRIMARY KEY NOT NULL,
                    seed_weight INTEGER NOT NULL
                ) WITHOUT ROWID;
                CREATE TABLE curated_cantonese_next (
                    prefix TEXT NOT NULL, word TEXT NOT NULL, seed_weight INTEGER NOT NULL,
                    PRIMARY KEY (prefix, word)
                ) WITHOUT ROWID;
                CREATE INDEX idx_curated_cantonese_next_rank
                    ON curated_cantonese_next(prefix, seed_weight DESC, word);
            """)
            db.executemany("INSERT INTO informal_terms VALUES (?,?,?,?)", [
                (lang, key, display, kind)
                for (lang, key), (display, kind) in sorted(terms.items())
            ])
            db.executemany("INSERT INTO informal_ngrams VALUES (?,?,?,?)", [
                (*identity, count) for identity, count in sorted(latin.items())
            ])
            db.executemany("INSERT INTO curated_cantonese_words VALUES (?,?)", sorted(words.items()))
            db.executemany("INSERT INTO curated_cantonese_ngrams VALUES (?,?)", sorted(chars.items()))
            db.executemany("INSERT INTO curated_cantonese_next VALUES (?,?,?)", [
                (*pair, count) for pair, count in sorted(continuations.items())
            ])
        if db.execute("PRAGMA quick_check").fetchone() != ("ok",):
            raise RuntimeError("Curated model SQLite integrity check failed")
        return {"terms": len(terms), "latin_contexts": len(latin),
                "cantonese_words": len(words), "cantonese_ngrams": len(chars),
                "cantonese_continuations": len(continuations)}
    finally:
        db.close()


if __name__ == "__main__":
    path = Path(sys.argv[1]) if len(sys.argv) == 2 else Path("JyutpingResources/jyutping.sqlite3")
    print("Curated informal seed model:", install(path))
