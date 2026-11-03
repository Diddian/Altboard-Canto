"""Regression checks for the five pinned Fcitx5 table data formats."""
import importlib.util
import pathlib
import sqlite3
import tempfile
import unittest
from unittest import mock

SCRIPT = pathlib.Path(__file__).with_name("build-chinese-shapes.py")
SPEC = importlib.util.spec_from_file_location("chinese_shapes_builder", SCRIPT)
BUILDER = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(BUILDER)


class ChineseShapesTests(unittest.TestCase):
    def test_cangjie_three_five_and_quick_codes(self):
        example = ("键码=abcdefghijklmnopqrstuvwxyz\n提示=&\n"
                   "码长=6\n[数据]\n&a 日\na 日\nab 明\n"
                   "ab 明\nceoi 候\n")
        words = list(BUILDER.parse_table(example.encode(), "cangjie3"))
        self.assertEqual(words[0][:2], ("a", "日"))
        self.assertEqual(words[1][:2], ("ab", "明"))
        self.assertEqual(len([e for e in words if e[0] == "ab"]), 1)
        self.assertEqual(len(list(BUILDER.parse_table(
            example.encode(), "quick3"))), 2)
        self.assertEqual(len(list(BUILDER.parse_table(
            example.encode(), "cangjie5"))), 3)

    def test_stroke5_key_order_and_codes(self):
        example = ("Length=5\nKeyCode=nm,./\n[Data]\n"
                   "&n ㄣ\nm 一\n/ 丨\n, 人\n. 丶\nn 乙\n"
                   ",/nmm 的\n,/nmm 的\n")
        rows = list(BUILDER.parse_table(example.encode(), "stroke5"))
        self.assertEqual([row[0] for row in rows[:5]], ["m", "/", ",", ".", "n"])
        self.assertEqual(len(rows), 6)

    def test_rime_stroke_normalization_and_long_codes(self):
        raw = ("---\nname: stroke\n...\n"
               "一\th\n丨\ts\n丿\tp\n丶\tn\n乛\tz\n"
               "字\thspnzhspnz\n字\thspnzhspnz\n")
        rows = list(BUILDER.parse_rime_stroke(raw.encode("utf-8")))
        self.assertEqual([code for code, _, _ in rows],
                         ["m", "/", ",", ".", "n", "m/,.nm/,.n"])
        self.assertEqual(len(rows), 6)

    def test_pinned_upstream_hash_contract(self):
        self.assertEqual(set(BUILDER.SOURCES), {
            "quick3", "quick5", "cangjie3", "cangjie5", "stroke5"
        })
        for digest in BUILDER.SOURCES.values():
            self.assertEqual(len(digest), 40)
        self.assertEqual(len(BUILDER.RIME_STROKE_BLOB), 40)

    def test_generation_and_dictionary_validation(self):
        # Use fixture files; no network requests or real user's typing data.
        rows = "\n".join(f"ab 字{i:04d}" for i in range(3101)) + "\n"
        # Distinct words include ASCII suffixes in this fixture, which are
        # accepted by the table importer but never shown as actual CJK data.
        with tempfile.TemporaryDirectory() as folder:
            path = pathlib.Path(folder)
            paths = {}
            for name in BUILDER.SOURCES:
                payload = f"[Data]\na 字\naa 昌\n{rows}".encode()
                if name == "stroke5":
                    payload = ("[Data]\n" + "\n".join(
                        f"m {i:04d}" for i in range(3101)
                    ) + "\n").encode()
                (path / f"{name}.txt").write_bytes(payload)
                paths[name] = BUILDER.SOURCES[name]
            hashes = {name: BUILDER.github_blob_sha((path / f"{name}.txt").read_bytes())
                      for name in BUILDER.SOURCES}
            rime_source = ("---\nname: stroke\n...\n" + "\n".join(
                f"字{i:04d}\thspnz" for i in range(3101)
            ) + "\n").encode("utf-8")
            with mock.patch.dict(BUILDER.SOURCES, hashes, clear=True), \
                 mock.patch.object(BUILDER, "RIME_STROKE_BLOB",
                                   BUILDER.github_blob_sha(rime_source)):
                result = BUILDER.compile_database(
                    path, path / "table.sqlite3",
                    path / "no-jyutping.sqlite3", rime_source=rime_source
                )
            self.assertEqual(set(result), set(BUILDER.SOURCES) | {"rime-stroke"})
            db = sqlite3.connect(path / "table.sqlite3")
            try:
                self.assertEqual(db.execute("PRAGMA quick_check").fetchone(), ("ok",))
                self.assertEqual(db.execute(
                    "SELECT COUNT(DISTINCT variant) FROM entries WHERE method='quick'"
                ).fetchone()[0], 2)
                self.assertEqual(db.execute(
                    "SELECT COUNT(*) FROM entries WHERE method='stroke' "
                    "AND source='rime-stroke' AND code='m/,.n'"
                ).fetchone()[0], 3101)
                self.assertGreater(db.execute(
                    "SELECT COUNT(*) FROM stroke_prefix WHERE prefix='m'"
                ).fetchone()[0], 0)
                self.assertEqual(db.execute(
                    "SELECT COUNT(*) FROM entries WHERE method='stroke' "
                    "AND source='stroke5'"
                ).fetchone()[0], 3101)
            finally:
                db.close()


if __name__ == "__main__":
    unittest.main()
