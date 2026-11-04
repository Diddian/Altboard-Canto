"""Deterministic offline Cantonese corpus-count regression tests."""
import importlib.util
from pathlib import Path
import sqlite3
import tempfile
import unittest

SCRIPT = Path(__file__).with_name("build-cantonese-ngrams.py")
SPEC = importlib.util.spec_from_file_location("cantonese_ngram_builder", SCRIPT)
BUILDER = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(BUILDER)

FIXTURE = ("@UTF8\n@Begin\n*XXA:\t你 都 唔 識 .\n"
           "%mor:\tr|nei5 d|dou1 v|m4 v|sik1 .\n"
           "*XXB:\t可能 呀 ， 耶穌 !\n"
           "%mor:\tvu|ho2nang4 y|aa3 , n|je4sou1 !\n"
           "*XXA:\t你 都\n\t唔 識 .\n%mor:\tother\n")


class CorpusNgramTests(unittest.TestCase):
    def test_tokenization_and_sentence_boundaries(self):
        utt = list(BUILDER.utterances(FIXTURE))
        self.assertEqual(utt, ["你 都 唔 識 .", "可能 呀 ， 耶穌 !", "你 都 唔 識 ."])
        words, grams, turns = BUILDER.aggregate([("fixture.cha", FIXTURE.encode())])
        self.assertEqual(turns, 3)
        self.assertEqual(words["識"], 2)
        self.assertEqual(grams["你都"], 2)
        self.assertEqual(grams["都唔識"], 2)
        self.assertEqual(grams["可能"], 1)
        self.assertEqual(grams["耶穌"], 1)
        self.assertEqual(grams["識可"], 0)
        self.assertEqual(grams["呀耶"], 0)
        self.assertNotIn("r|nei", words)

    def test_clean_sqlite_rebuild_is_byte_identical(self):
        with tempfile.TemporaryDirectory() as tmp:
            sources = [("fixture.cha", FIXTURE.encode())]
            files = []
            results = []
            for index in (1, 2):
                path = Path(tmp) / f"ngram-{index}.sqlite3"
                db = sqlite3.connect(path)
                db.execute("CREATE TABLE entries (word TEXT)")
                db.commit()
                db.close()
                results.append(BUILDER.install_counts(path, sources))
                files.append(path.read_bytes())
                db = sqlite3.connect(path)
                try:
                    self.assertEqual(db.execute("PRAGMA quick_check").fetchone(), ("ok",))
                    self.assertEqual(db.execute(
                        "SELECT frequency FROM corpus_ngrams WHERE gram='你都'"
                    ).fetchone(), (2,))
                    plan = " ".join(str(row) for row in db.execute(
                        "EXPLAIN QUERY PLAN SELECT frequency FROM corpus_ngrams WHERE gram=?",
                        ("你都",)
                    ))
                    self.assertIn("PRIMARY KEY", plan.upper())
                finally:
                    db.close()
            self.assertEqual(results[0], results[1])
            self.assertEqual(files[0], files[1])

    def test_missing_lexicon_aborts_without_creating_tables(self):
        with tempfile.TemporaryDirectory() as tmp:
            path = Path(tmp) / "ngram.sqlite3"
            sqlite3.connect(path).close()
            with self.assertRaises(ValueError):
                BUILDER.install_counts(path, [("fixture.cha", FIXTURE.encode())])


if __name__ == "__main__":
    unittest.main()
