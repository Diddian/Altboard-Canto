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
        self.assertEqual(MOD.yale_syllable("zau6"), "jau")
        self.assertEqual(MOD.yale_syllable("caan4"), "chaan")
        self.assertEqual(MOD.sidney_lau_syllable("caan4"), "chaan")
        self.assertEqual(MOD.yale_syllable("faan6"), "faan")
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
                    {row[0] for row in db.execute("SELECT compact FROM entries WHERE word='據'")}, {"geoi2", "geoi3"}
                )
            finally:
                db.close()

    def test_traditional_and_jyutping_aliases_for_common_words(self):
        with tempfile.TemporaryDirectory() as tmp:
            output = pathlib.Path(tmp) / "common.sqlite3"
            MOD.compile_database(
                "殘\tcaan4\n讚\tzaan3\n哪\tnaa5\n".encode(), output,
                verify_upstream=False
            )
            db = sqlite3.connect(output)
            try:
                for column, code, word in (
                    ("plain", "caan", "殘"), ("yale", "chaan", "殘"),
                    ("sidney", "chaan", "殘"), ("plain", "zaan", "讚"),
                    ("yale", "jaan", "讚"), ("sidney", "jaan", "讚"),
                    ("plain", "naa", "哪")
                ):
                    with self.subTest(column=column, code=code):
                        self.assertEqual(db.execute(
                            f"SELECT word FROM entries WHERE {column}=? AND word=?",
                            (code, word)
                        ).fetchone(), (word,))
            finally:
                db.close()

    def test_open_aa_and_distinct_sidney_finals(self):
        examples = {
            "naa5": ("na", "na"), "naa4": ("na", "na"),
            "caan4": ("chaan", "chaan"),
            "zaan3": ("jaan", "jaan"),
            "go3": ("go", "goh"), "wo3": ("wo", "woh"),
            "po4": ("po", "poh"), "gou1": ("gou", "go"),
            "fu3": ("fu", "foo"), "bui1": ("bui", "booi"),
            "gun1": ("gun", "goon"), "gut1": ("gut", "goot"),
            "ceot1": ("cheut", "chut"),
            "zeon1": ("jeun", "jun"),
            "jyun4": ("yun", "yuen"),
            "jyu5": ("yu", "yue"),
            "jyut6": ("yut", "yuet"),
            "seoi2": ("seui", "sui"), "syu1": ("syu", "sue"),
            "ngaa5": ("nga", "nga"),
            "ng5": ("ng", "ng"), "m4": ("m", "m"),
        }
        for reading, (yale, sidney) in examples.items():
            with self.subTest(syllable=reading):
                self.assertEqual(MOD.yale_syllable(reading), yale)
                self.assertEqual(MOD.sidney_lau_syllable(reading), sidney)

    def test_na_exact_readings_and_priority_for_all_indexed_schemes(self):
        with tempfile.TemporaryDirectory() as tmp:
            output = pathlib.Path(tmp) / "na.sqlite3"
            MOD.compile_database(b"\xe4\xbd\xa0\xe5\xa5\xbd\tnei5 hou2\n", output, verify_upstream=False)
            db = sqlite3.connect(output)
            try:
                for column in ("yale", "sidney"):
                    with self.subTest(column=column):
                        rows = db.execute(
                            f"SELECT word FROM entries WHERE {column}=? "
                            "ORDER BY priority LIMIT 20", ("na",)
                        ).fetchall()
                        unique = list(dict.fromkeys(word for (word,) in rows))
                        self.assertEqual(unique[:4], ["哪", "那", "拿", "嗱"])
                expected = {
                    "哪": {"naa1", "naa4", "naa5"},
                    "那": {"naa5", "naa6"},
                    "拿": {"naa4"}, "嗱": {"naa4"}
                }
                for word, readings in expected.items():
                    got = {reading for (reading,) in db.execute(
                        "SELECT romanization FROM entries WHERE word=? "
                        "AND yale=? ORDER BY priority", (word, "na")
                    ).fetchall()}
                    self.assertTrue(readings.issubset(got), (word, got))
                for word, plain, sidney in (
                    ("喎", "wo", "woh"),
                    ("個", "go", "goh"),
                    ("婆", "po", "poh"),
                ):
                    self.assertIsNotNone(db.execute(
                        "SELECT 1 FROM entries WHERE plain=? AND word=? LIMIT 1",
                        (plain, word)
                    ).fetchone())
                    self.assertIsNotNone(db.execute(
                        "SELECT 1 FROM entries WHERE sidney=? AND word=? LIMIT 1",
                        (sidney, word)
                    ).fetchone())
                self.assertEqual(db.execute("PRAGMA quick_check").fetchone(), ("ok",))
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
