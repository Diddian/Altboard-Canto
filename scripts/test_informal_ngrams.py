"""Curated multilingual seed model, kept separate from observed HKCanCor counts."""
import importlib.util
from pathlib import Path
import sqlite3
import tempfile
import unittest

SCRIPT = Path(__file__).with_name("build-informal-ngrams.py")
SPEC = importlib.util.spec_from_file_location("informal_ngram_builder", SCRIPT)
BUILDER = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(BUILDER)


class InformalNgramTests(unittest.TestCase):
    def test_separate_corpus_and_editorial_patterns(self):
        with tempfile.TemporaryDirectory() as tmp:
            path = Path(tmp) / "data.sqlite3"
            with sqlite3.connect(path) as db:
                db.execute("CREATE TABLE entries(word TEXT)")
                db.execute("CREATE TABLE corpus_ngrams(gram TEXT PRIMARY KEY, frequency INTEGER)")
                db.execute("INSERT INTO corpus_ngrams VALUES ('你好', 123)")
            counts = BUILDER.install(path)
            self.assertGreaterEqual(counts["terms"], 60)
            self.assertGreaterEqual(counts["latin_contexts"], 150)
            with sqlite3.connect(path) as db:
                self.assertEqual(db.execute("SELECT frequency FROM corpus_ngrams WHERE gram='你好'").fetchone(), (123,))
                self.assertEqual(db.execute("SELECT display FROM informal_terms WHERE language='en' AND key='brb'").fetchone(), ("brb",))
                self.assertEqual(db.execute("SELECT display FROM informal_terms WHERE language='de' AND key='bzw'").fetchone(), ("bzw.",))
                self.assertEqual(db.execute("SELECT display FROM informal_terms WHERE language='yue' AND key='mnyy'").fetchone(), ("MNYY",))
                for language, history, token in [
                    ("de", "ich", "check"), ("de", "ich", "checke"),
                    ("de", "das ist", "safe"), ("en", "idk", "what"),
                    ("en", "好", "tired"), ("de", "好", "lost"),
                ]:
                    self.assertIsNotNone(db.execute(
                        "SELECT seed_weight FROM informal_ngrams WHERE language=? AND history=? AND token=?",
                        (language, history, token)
                    ).fetchone(), (language, history, token))
                self.assertGreater(db.execute("SELECT seed_weight FROM curated_cantonese_ngrams WHERE gram='世一'").fetchone()[0], 0)
                for rare_word in ("罨耷", "噏耷", "褸丘", "烏搲", "污搲",
                                  "奀挑鬼命", "論盡", "黑瞇擝", "窿窿罅罅"):
                    with self.subTest(rare=rare_word):
                        self.assertGreater(db.execute(
                            "SELECT seed_weight FROM curated_cantonese_words WHERE word=?",
                            (rare_word,)
                        ).fetchone()[0], 0)
                for rare_gram in ("罨耷", "褸丘", "烏搲", "黑瞇", "罅罅"):
                    self.assertGreater(db.execute(
                        "SELECT seed_weight FROM curated_cantonese_ngrams WHERE gram=?",
                        (rare_gram,)
                    ).fetchone()[0], 0)
                self.assertIsNotNone(db.execute(
                    "SELECT word FROM curated_cantonese_next "
                    "WHERE prefix='好' AND word='罨耷'"
                ).fetchone())
                self.assertGreater(db.execute("SELECT seed_weight FROM curated_cantonese_words WHERE word='世一'").fetchone()[0], 0)
                self.assertGreater(db.execute("SELECT seed_weight FROM curated_cantonese_words WHERE word='壽司'").fetchone()[0], 0)
                self.assertIsNone(db.execute("SELECT seed_weight FROM curated_cantonese_words WHERE word='本番'").fetchone())
                self.assertIsNone(db.execute("SELECT seed_weight FROM curated_cantonese_words WHERE word='の'").fetchone())
                self.assertIsNotNone(db.execute("SELECT word FROM curated_cantonese_next WHERE prefix='係' AND word='天花板'").fetchone())
                self.assertIsNotNone(db.execute("SELECT word FROM curated_cantonese_next WHERE prefix='真係' AND word='世一'").fetchone())
                self.assertEqual(db.execute("PRAGMA quick_check").fetchone(), ("ok",))
            self.assertEqual(BUILDER.install(path), counts)

    def test_bad_source_data_is_rejected_before_modifying_sqlite(self):
        with tempfile.TemporaryDirectory() as tmp:
            directory = Path(tmp)
            (directory / "informal-terms.tsv").write_text("en\tbrb\tshort\n", encoding="utf-8")
            (directory / "informal-patterns.tsv").write_text("unknown\tHello there\n", encoding="utf-8")
            with self.assertRaises(ValueError):
                BUILDER.collect(directory)

    def test_requires_existing_lexicon(self):
        with tempfile.TemporaryDirectory() as tmp:
            path = Path(tmp) / "blank.sqlite3"
            sqlite3.connect(path).close()
            with self.assertRaises(ValueError):
                BUILDER.install(path)


if __name__ == "__main__":
    unittest.main()
