import importlib.util
import pathlib
import sqlite3
import tempfile
import unittest

ROOT = pathlib.Path(__file__).resolve().parent.parent
SPEC = importlib.util.spec_from_file_location("jyutping_builder", ROOT / "scripts" / "build-jyutping-lexicon.py")
MOD = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(MOD)


class YaleAliasTests(unittest.TestCase):
    def test_initials(self):
        self.assertEqual(MOD.yale_syllable("jat6"), "yat")
        self.assertEqual(MOD.yale_syllable("zi1"), "ji")
        self.assertEqual(MOD.yale_syllable("ce1"), "che")
        self.assertEqual(MOD.yale_syllable("goeng1"), "geung")

    def test_today(self):
        self.assertEqual(MOD.yale_spelling("gam1 jat6"), "gamyat")

    def test_index(self):
        with tempfile.TemporaryDirectory() as tmp:
            output = pathlib.Path(tmp) / "jyutping.sqlite3"
            MOD.compile_database("今日\tgam1 jat6\n你好\tnei5 hou2\n".encode(), output, verify_upstream=False)
            db = sqlite3.connect(output)
            try:
                self.assertEqual(db.execute("SELECT word FROM entries WHERE yale=?", ("gamyat",)).fetchone(), ("今日",))
                self.assertEqual(db.execute("SELECT word FROM entries WHERE plain=?", ("gamjat",)).fetchone(), ("今日",))
                self.assertIsNotNone(db.execute("SELECT name FROM sqlite_master WHERE name='idx_entries_yale'").fetchone())
            finally:
                db.close()


if __name__ == "__main__":
    unittest.main()
