"""HK Japanese-influenced Cantonese spellings and exact suggestion safeguards."""
import importlib.util
from pathlib import Path
import sqlite3
import tempfile
import unittest

HERE = Path(__file__).resolve().parent
SPEC = importlib.util.spec_from_file_location(
    "jyutping_builder", HERE / "build-jyutping-lexicon.py")
BUILDER = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(BUILDER)
SOURCE = HERE / "hk-japanese-loanwords.tsv"


class HKJapaneseLexiconTests(unittest.TestCase):
    def test_curated_metadata_and_cantonese_readings(self):
        items = BUILDER.load_hk_japanese_index(SOURCE)
        self.assertGreaterEqual(len(items), 175)
        lookup = {word: (reading, domain, usage, alt)
                  for word, reading, domain, usage, alt in items}
        self.assertEqual(lookup["の"], ("zi1", "orthography", "common", "之"))
        self.assertEqual(lookup["本番"][:3], ("bun2 faan1", "media", "context"))
        self.assertEqual(lookup["放題"][0], "fong3 tai4")
        self.assertEqual(lookup["聲優"][0], "sing1 jau1")
        self.assertEqual(lookup["課金"][0], "fo3 gam1")
        self.assertEqual(lookup["壽司"][0], "sau6 si1")
        self.assertEqual(lookup["萌"][0], "mang4")
        self.assertTrue(all(len(surface) == len(reading.split())
                            for surface, reading, _, _, _ in items))
        self.assertEqual(len(items), len({row[0] for row in items}))

    def test_phonetic_indexes_and_provenance_table(self):
        with tempfile.TemporaryDirectory() as directory:
            dest = Path(directory) / "lexicon.sqlite3"
            BUILDER.compile_database(
                "之\tzi1\n本\tbun2\n番\tfaan1\n".encode(), dest,
                verify_upstream=False
            )
            with sqlite3.connect(dest) as db:
                for column, input_text, expected in (
                    ("plain", "zi", "の"), ("compact", "zi1", "の"),
                    ("yale", "ji", "の"), ("sidney", "ji", "の"),
                    ("plain", "bunfaan", "本番"),
                    ("yale", "bunfaan", "本番"),
                    ("sidney", "boonfaan", "本番"),
                ):
                    with self.subTest(column=column, input=input_text):
                        self.assertEqual(
                            db.execute(
                                f"SELECT word FROM entries WHERE {column}=? AND word=? LIMIT 1",
                                (input_text, expected)
                            ).fetchone(), (expected,)
                        )
                self.assertIsNotNone(db.execute(
                    "SELECT word FROM entries WHERE word='之' AND plain='zi'"
                ).fetchone())
                self.assertEqual(db.execute(
                    "SELECT usage FROM hk_japanese_lexicon WHERE word='本番'"
                ).fetchone(), ("context",))
                self.assertEqual(db.execute(
                    "SELECT alternative FROM hk_japanese_lexicon WHERE word='の'"
                ).fetchone(), ("之",))
                self.assertGreaterEqual(db.execute(
                    "SELECT count(*) FROM hk_japanese_lexicon"
                ).fetchone()[0], 175)
                self.assertEqual(db.execute("PRAGMA quick_check").fetchone(), ("ok",))
                for column in ("plain", "yale", "sidney"):
                    plan = " ".join(str(r) for r in db.execute(
                        f"EXPLAIN QUERY PLAN SELECT word FROM entries WHERE {column}=?",
                        ("ji",)
                    ))
                    self.assertIn("INDEX", plan.upper())

    def test_rejects_invalid_and_duplicate_entries(self):
        with tempfile.TemporaryDirectory() as directory:
            file = Path(directory) / "bad.tsv"
            file.write_text("の\tzi1\torthography\tcommon\t之\n"
                            "の\tzi1\torthography\tcommon\t之\n",
                            encoding="utf-8")
            with self.assertRaises(ValueError):
                BUILDER.load_hk_japanese_index(file)


if __name__ == "__main__":
    unittest.main()
