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
        self.assertEqual(MOD.yale_syllable("zoeng1"), "jeung")
        self.assertEqual(MOD.yale_syllable("jyu5"), "yu")
        self.assertEqual(MOD.yale_syllable("jyun4"), "yun")
        self.assertEqual(MOD.yale_syllable("jyut6"), "yut")

    def test_sidney_lau_spelling(self):
        cases = {
            "keoi5": "kui", "seoi2": "sui", "neoi5": "nui",
            "deoi3": "dui", "heoi3": "hui", "ceon1": "chun",
            "syu1": "sue", "hyut3": "huet", "gou1": "go",
            "hou2": "ho", "lou6": "lo", "geoi3": "gui",
            "zeoi3": "jui", "jyun4": "yuen", "jyu5": "yue",
            "zeoi1": "jui", "ceot1": "chut", "jyut6": "yuet",
            "ce1": "che", "zi1": "ji", "zoeng1": "jeung",
            "goeng1": "geung", "soeng2": "seung",
        }
        for jyutping, expected in cases.items():
            with self.subTest(jyutping=jyutping):
                self.assertEqual(MOD.sidney_lau_syllable(jyutping), expected)

    def test_canonical_tones_remain_distinct_in_index(self):
        with tempfile.TemporaryDirectory() as tmp:
            output = pathlib.Path(tmp) / "tones.sqlite3"
            MOD.compile_database("據\tgeoi3\n據\tgeoi2\n".encode(), output, verify_upstream=False)
            db = sqlite3.connect(output)
            try:
                self.assertEqual(
                    db.execute("SELECT COUNT(*) FROM entries WHERE word='據'").fetchone()[0], 2
                )
                self.assertEqual(
                    {row[0] for row in db.execute("SELECT compact FROM entries")}, {"geoi2", "geoi3"}
                )
            finally:
                db.close()

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
                self.assertIsNotNone(db.execute("SELECT name FROM sqlite_master WHERE name='idx_entries_sidney'").fetchone())
            finally:
                db.close()


if __name__ == "__main__":
    unittest.main()
