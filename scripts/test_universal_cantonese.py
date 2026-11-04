"""Regression tests for one indexed Jyutping/Yale/Sidney Lau candidate engine."""
import importlib.util
import pathlib
import sqlite3
import tempfile
import unittest

ROOT = pathlib.Path(__file__).resolve().parent.parent
SPEC = importlib.util.spec_from_file_location("canto_builder", ROOT / "scripts" / "build-jyutping-lexicon.py")
BUILDER = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(BUILDER)

ENTRIES = {
    "佢": "keoi5", "水": "seoi2", "女": "neoi5",
    "對": "deoi3", "去": "heoi3", "春": "ceon1",
    "書": "syu1", "血": "hyut3", "高": "gou1",
    "好": "hou2", "路": "lou6", "據": "geoi3",
    "最": "zeoi3", "完": "jyun4", "語": "jyu5",
    "出": "ceot1", "月": "jyut6", "車": "ce1",
    "知": "zi1", "張": "zoeng1", "根據": "gan1 geoi3",
}
CASES = {
    "佢": ("keoi", "keui", "kui"),
    "水": ("seoi", "seui", "sui"),
    "女": ("neoi", "neui", "nui"),
    "對": ("deoi", "deui", "dui"),
    "去": ("heoi", "heui", "hui"),
    "春": ("ceon", "cheun", "chun"),
    "書": ("syu", "syu", "sue"),
    "血": ("hyut", "hyut", "huet"),
    "高": ("gou", "gou", "go"),
    "好": ("hou", "hou", "ho"),
    "路": ("lou", "lou", "lo"),
    "據": ("geoi", "geui", "gui"),
    "最": ("zeoi", "jeui", "jui"),
    "完": ("jyun", "yun", "yuen"),
    "語": ("jyu", "yu", "yue"),
    "出": ("ceot", "cheut", "chut"),
    "月": ("jyut", "yut", "yuet"),
    "車": ("ce", "che", "che"),
    "知": ("zi", "ji", "ji"),
    "張": ("zoeng", "jeung", "jeung"),
    "根據": ("gangeoi", "gangeui", "gangui"),
}

class UniversalCantoneseTests(unittest.TestCase):
    def test_structural_aliases_and_collisions(self):
        # Each scheme must be an alias for the same canonical spelling, not
        # a separately translated dictionary or a second tone reading.
        for word, readings in CASES.items():
            plain, yale, sidney = readings
            with self.subTest(word=word):
                self.assertEqual(BUILDER.yale_spelling(ENTRIES[word]), yale)
                self.assertEqual(BUILDER.sidney_lau_spelling(ENTRIES[word]), sidney)
                self.assertNotIn("yyu", yale)
                self.assertNotIn("yyun", yale)
                self.assertNotIn("yyut", yale)
        self.assertEqual(BUILDER.sidney_lau_syllable("zoeng1"), "jeung")
        self.assertEqual(BUILDER.sidney_lau_syllable("goeng1"), "geung")
        self.assertEqual(BUILDER.yale_syllable("jyun4"), "yun")

    def test_sqlite_index_used_for_all_three_spelling_systems(self):
        with tempfile.TemporaryDirectory() as tmp:
            dest = pathlib.Path(tmp) / "indexed.sqlite3"
            source = "".join(f"{word}\t{reading}\n" for word, reading in ENTRIES.items())
            BUILDER.compile_database(source.encode("utf-8"), dest, verify_upstream=False)
            db = sqlite3.connect(dest)
            try:
                for col in ("plain", "yale", "sidney"):
                    plan = " ".join(str(row) for row in db.execute(
                        f"EXPLAIN QUERY PLAN SELECT word FROM entries WHERE {col}=?",
                        ("kui",),
                    ).fetchall())
                    with self.subTest(column=col):
                        self.assertIn("INDEX", plan.upper())
                self.assertEqual(db.execute("PRAGMA quick_check").fetchone(), ("ok",))
            finally:
                db.close()

    def test_reviewed_long_phrases_and_mixed_scheme_aliases(self):
        with tempfile.TemporaryDirectory() as tmp:
            dest = pathlib.Path(tmp) / "mixed.sqlite3"
            BUILDER.compile_database("你好\tnei5 hou2\n".encode(), dest, verify_upstream=False)
            db = sqlite3.connect(dest)
            try:
                for spelling in ("nghaiama", "nghaiaamaa", "nghaiamaa", "nghaiaama"):
                    with self.subTest(spelling=spelling):
                        self.assertEqual(db.execute(
                            "SELECT word FROM mixed_aliases WHERE alias=? "
                            "ORDER BY priority LIMIT 1", (spelling,)
                        ).fetchone(), ("唔係呀嘛",))
                self.assertEqual(db.execute(
                    "SELECT word FROM entries WHERE plain=? AND word=? LIMIT 1",
                    ("mhaiaamaa", "唔係呀嘛")
                ).fetchone(), ("唔係呀嘛",))
                self.assertEqual(db.execute(
                    "SELECT word FROM mixed_aliases WHERE alias=? AND word=? LIMIT 1",
                    ("jyutyue", "粵語")
                ).fetchone(), ("粵語",))
                plan = " ".join(map(str, db.execute(
                    "EXPLAIN QUERY PLAN SELECT word FROM mixed_aliases WHERE alias=?",
                    ("nghaiama",)
                ).fetchall()))
                self.assertIn("INDEX", plan.upper())
            finally:
                db.close()

    def test_daily_dialogue_long_phrases_and_corrections(self):
        # Additional entries are explicitly curated instead of arbitrary
        # combinations of any syllables in the upstream dictionary.
        supplemental = (ROOT / "scripts" / "cantonese-phrases.tsv").read_text(encoding="utf-8")
        known = dict(line.split("\t", 1) for line in supplemental.splitlines())
        for word, reading in {
            "我": "ngo5", "你": "nei5", "妳": "naai5",
            "佢": "keoi5", "她": "taa1", "他": "taa1",
            "哪": "naa5", "哪個": "naa5 go3",
            "啫係": "ze1 hai6", "呢個": "ni1 go3",
            "嗰個": "go2 go3", "喎": "wo3", "個": "go3",
            "我今日冇瞓過覺": "ngo5 gam1 jat6 mou5 fan3 gwo3 gaau3"
        }.items():
            with self.subTest(basic=word):
                self.assertEqual(known[word], reading)
        self.assertEqual(known["你食咗飯未呀"], "nei5 sik6 zo2 faan6 mei6 aa3")
        self.assertEqual(known["食塞米啦你"], "sik6 sak1 mai5 laa1 nei5")
        self.assertEqual(known["幾快"], "gei2 faai3")
        self.assertEqual(known["其實"], "kei4 sat6")
        self.assertEqual(known["我係"], "ngo5 hai6")
        self.assertEqual(known["你係"], "nei5 hai6")
        self.assertNotIn("食塞埋你", known)
        self.assertGreaterEqual(sum(len(word) >= 9 for word in known), 500)
        self.assertTrue(all(len(word) == len(reading.split()) for word, reading in known.items()))
        phrase = "我想問吓你有冇時間同我哋傾一傾"
        plain = "".join(char for char in known[phrase] if char.isascii() and char.isalpha())
        self.assertGreater(len(plain), 48)
        self.assertLessEqual(len(plain), 96)
        with tempfile.TemporaryDirectory() as tmp:
            dest = pathlib.Path(tmp) / "long.sqlite3"
            BUILDER.compile_database("你好\tnei5 hou2\n".encode(), dest, verify_upstream=False)
            db = sqlite3.connect(dest)
            try:
                self.assertEqual(db.execute(
                    "SELECT word FROM entries WHERE plain=? AND word=? LIMIT 1",
                    (plain, phrase)
                ).fetchone(), (phrase,))
                # The incremental composer can join exact short entries;
                # no full-length phrase needs to exist for this combination.
                self.assertEqual(db.execute(
                    "SELECT word FROM entries WHERE plain=? AND word=? LIMIT 1",
                    ("keisat", "其實")
                ).fetchone(), ("其實",))
                self.assertEqual(db.execute(
                    "SELECT word FROM entries WHERE plain=? AND word=? LIMIT 1",
                    ("ngohai", "我係")
                ).fetchone(), ("我係",))
                self.assertEqual(db.execute("PRAGMA quick_check").fetchone(), ("ok",))
            finally:
                db.close()

    def test_short_prefix_backfills_single_characters_before_limit(self):
        # Longer phrases can consume the first 24 prefix matches, leaving
        # the compact candidate strip almost empty after length filtering.
        db = sqlite3.connect(":memory:")
        try:
            db.execute("CREATE TABLE entries (word TEXT, romanization TEXT, "
                       "plain TEXT, yale TEXT, sidney TEXT, priority INTEGER)")
            for i in range(30):
                db.execute("INSERT INTO entries VALUES (?, ?, ?, ?, ?, ?)",
                           (f"短詞{i}", "gaa1 maa1", f"gaaa{i:02}", f"gaaa{i:02}",
                            f"gaaa{i:02}", i))
            for i, character in enumerate("㗎嘎噶架家加假嘉嫁價佳街皆戒"):
                db.execute("INSERT INTO entries VALUES (?, ?, ?, ?, ?, ?)",
                           (character, "gaa1", f"gaa{i:02}", f"gaa{i:02}",
                            f"gaa{i:02}", i + 30))
            shallow = db.execute(
                "SELECT word FROM entries WHERE plain>=? AND plain<? "
                "ORDER BY priority LIMIT ?", ("ga", "ga{", 24)
            ).fetchall()
            self.assertFalse(any(len(word) == 1 for (word,) in shallow))
            backfill = db.execute(
                "SELECT word FROM entries WHERE plain>=? AND plain<? "
                "AND length(word)=1 ORDER BY priority LIMIT ?",
                ("ga", "ga{", 24)
            ).fetchall()
            self.assertGreaterEqual(len(backfill), 12)
            self.assertTrue(all(len(word) == 1 for (word,) in backfill))
            dictionary = (ROOT / "SayboardKeyboard" / "JyutpingDictionary.swift").read_text(
                encoding="utf-8"
            )
            self.assertIn("results.count < 24", dictionary)
            # Both compact and expanded lookup use the same source order
            # and per-index depth; only final output count may differ.
            self.assertIn("let queryLimit = 72", dictionary)
            self.assertIn("Array(ordered.prefix(boundedLimit))", dictionary)
            self.assertIn("maxChunks: 3", dictionary)
            self.assertIn("var paths = Array<[JyutpingCandidate]?>", dictionary)
            self.assertIn("AND length(word)=1 ORDER BY priority LIMIT ?", dictionary)
        finally:
            db.close()

    def test_ng_for_negative_particle_in_any_word_position(self):
        examples = {
            "會唔會": ("wui5 m4 wui5", "wuingwui"),
            "食唔食": ("sik6 m4 sik6", "sikngsik"),
            "但唔係": ("daan6 m4 hai6", "daannghai"),
            "你食唔食": ("nei5 sik6 m4 sik6", "neisikngsik"),
        }
        for word, (reading, alias) in examples.items():
            with self.subTest(word=word):
                self.assertIn(alias, BUILDER.negative_particle_aliases(word, reading))
        self.assertEqual(BUILDER.negative_particle_aliases("眼", "ngaan5"), [])
        self.assertEqual(BUILDER.negative_particle_aliases("銀行", "ngan4 hong4"), [])
        # Every existing curated 唔 entry must allow an ng spelling,
        # whether 唔 is at the start, in the middle or appears twice.
        supplemental = (ROOT / "scripts" / "cantonese-phrases.tsv").read_text(encoding="utf-8")
        negatives = dict(line.split("\t", 1) for line in supplemental.splitlines()
                         if "唔" in line.split("\t", 1)[0])
        self.assertGreaterEqual(len(negatives), 600)
        for word, reading in negatives.items():
            with self.subTest(word=word):
                self.assertTrue(BUILDER.negative_particle_aliases(word, reading))
        for word in ("唔好", "唔係", "唔洗", "唔使"):
            with self.subTest(common=word):
                self.assertIn(word, negatives)
        self.assertIn("nghou", BUILDER.negative_particle_aliases("唔好", "m4 hou2"))
        self.assertIn("ngho", BUILDER.negative_particle_aliases("唔好", "m4 hou2"))
        self.assertIn("ngsai", BUILDER.negative_particle_aliases("唔洗", "m4 sai2"))
        with tempfile.TemporaryDirectory() as tmp:
            dest = pathlib.Path(tmp) / "negation.sqlite3"
            source = "".join(
                f"{word}\t{reading}\n" for word, (reading, _) in examples.items()
            )
            BUILDER.compile_database(source.encode(), dest, verify_upstream=False)
            db = sqlite3.connect(dest)
            try:
                for word, (_, alias) in examples.items():
                    with self.subTest(word=word, alias=alias):
                        row = db.execute(
                            "SELECT word FROM mixed_aliases WHERE alias=? AND word=? LIMIT 1",
                            (alias, word),
                        ).fetchone()
                        self.assertEqual(row, (word,))
                for word, alias in [
                    ("唔好", "nghou"), ("唔好", "ngho"),
                    ("唔係", "nghai"), ("唔洗", "ngsai"),
                    ("唔使", "ngsai"), ("唔洗", "msai"),
                    ("唔使", "msai"),
                ]:
                    with self.subTest(word=word, spelling=alias):
                        column = "mixed_aliases" if alias.startswith("ng") else "entries"
                        field = "alias" if alias.startswith("ng") else "plain"
                        row = db.execute(
                            f"SELECT word FROM {column} WHERE {field}=? AND word=? LIMIT 1",
                            (alias, word),
                        ).fetchone()
                        self.assertEqual(row, (word,))
                self.assertEqual(db.execute("PRAGMA quick_check").fetchone(), ("ok",))
            finally:
                db.close()

    def test_all_three_indexes_and_tones(self):
        with tempfile.TemporaryDirectory() as tmp:
            dest = pathlib.Path(tmp) / "jyutping.sqlite3"
            source = "".join(f"{word}\t{reading}\n" for word, reading in ENTRIES.items())
            BUILDER.compile_database(source.encode("utf-8"), dest, verify_upstream=False)
            db = sqlite3.connect(dest)
            try:
                for word, inputs in CASES.items():
                    for column, spelling in zip(("plain", "yale", "sidney"), inputs):
                        with self.subTest(word=word, column=column, spelling=spelling):
                            found = db.execute(
                                f"SELECT word FROM entries WHERE {column}=? AND word=? LIMIT 1",
                                (spelling, word),
                            ).fetchone()
                            self.assertEqual(found, (word,))
                self.assertEqual(
                    db.execute("SELECT word FROM entries WHERE compact=?", ("geoi3",)).fetchone(),
                    ("據",),
                )
                self.assertIsNone(
                    db.execute("SELECT word FROM entries WHERE compact=?", ("geoi2",)).fetchone()
                )
            finally:
                db.close()

if __name__ == "__main__":
    unittest.main()
