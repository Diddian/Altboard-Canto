import importlib.util
import pathlib
import unittest

ROOT = pathlib.Path(__file__).resolve().parent.parent
SPEC = importlib.util.spec_from_file_location("emoji_builder", ROOT / "scripts" / "build-emoji-catalog.py")
MOD = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(MOD)


class EmojiCatalogTests(unittest.TestCase):
    def test_bundled_unicode_17_data_and_license(self):
        source = (ROOT / "scripts" / "data" / "emoji-test-17.0.txt").read_text(
            encoding="utf-8"
        )
        self.assertIn(MOD.VERSION, source)
        entries = MOD.parse_catalog(source)
        self.assertGreaterEqual(len(entries), 3000)
        self.assertIn(("Smileys & Emotion", "grinning face", "😀"), entries)
        notice = (ROOT / "scripts" / "data" / "UnicodeLicense.txt").read_text(
            encoding="utf-8"
        )
        self.assertTrue(notice.startswith("UNICODE LICENSE V3"))

    def test_recent_one_page_is_bounded_and_order_stable_while_open(self):
        catalog = (ROOT / "SayboardKeyboard" / "EmojiCatalog.swift").read_text(
            encoding="utf-8"
        )
        view = (ROOT / "SayboardKeyboard" / "Views" / "EmojiKeyboardView.swift").read_text(
            encoding="utf-8"
        )
        self.assertIn("static let recentPageSize = 24", catalog)
        self.assertIn("Array(values.prefix(recentPageSize))", catalog)
        self.assertIn("if saved.count > recentPageSize", catalog)
        self.assertIn("defaults?.set(bounded, forKey: recentKey)", catalog)
        self.assertIn("let bounded = boundedRecent(values)", catalog)
        self.assertIn(".onAppear { self.recent = EmojiCatalog.recent() }", view)
        self.assertIn("_ = EmojiCatalog.remember(choice)", view)
        self.assertNotIn("self.recent = EmojiCatalog.remember(choice)", view)
        self.assertIn("HStack(spacing: 4.kbScaled)", view)
        self.assertIn(".frame(width: 44.kbScaled, height: KeyboardChromeMetrics.keyHeight)", view)
        self.assertIn("count: 8", view)
        self.assertIn("by: 24", view)

    def test_fully_qualified_order_search_metadata(self):
        fixture = """# Version: 18.0
# group: Smileys & Emotion
1F600 ; fully-qualified # 😀 E1.0 grinning face
1F600 ; unqualified # 😀 E1.0 grinning face
1F469 200D 1F4BB ; fully-qualified # 👩‍💻 E4.0 woman technologist
# group: Flags
1F1ED 1F1F0 ; fully-qualified # 🇭🇰 E2.0 flag: Hong Kong SAR China
"""
        entries = MOD.parse_catalog(fixture)
        self.assertEqual(len(entries), 3)
        self.assertEqual(entries[0], ("Smileys & Emotion", "grinning face", "😀"))
        self.assertEqual(entries[1][2], "👩‍💻")
        self.assertEqual(entries[2][1], "flag: Hong Kong SAR China")


if __name__ == "__main__":
    unittest.main()
