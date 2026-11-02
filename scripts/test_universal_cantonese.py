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
