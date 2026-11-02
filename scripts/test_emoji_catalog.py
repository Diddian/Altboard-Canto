import importlib.util
import pathlib
import unittest

ROOT = pathlib.Path(__file__).resolve().parent.parent
SPEC = importlib.util.spec_from_file_location("emoji_builder", ROOT / "scripts" / "build-emoji-catalog.py")
MOD = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(MOD)


class EmojiCatalogTests(unittest.TestCase):
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

    def test_keeps_skin_tones_and_zwj_as_distinct_qualified_emoji(self):
        fixture = """# group: People & Body
1F44D ; fully-qualified # 👍 E0.6 thumbs up
1F44D 1F3FD ; fully-qualified # 👍🏽 E1.0 thumbs up: medium skin tone
1F44D 1F3FD ; minimally-qualified # 👍🏽 E1.0 thumbs up: medium skin tone
1F469 200D 1F4BB ; fully-qualified # 👩‍💻 E4.0 woman technologist
"""
        entries = MOD.parse_catalog(fixture)
        self.assertEqual(len(entries), 3)
        self.assertEqual(entries[1][1], "thumbs up: medium skin tone")
        self.assertEqual(entries[2][2], "👩‍💻")
        self.assertEqual(len({v[2] for v in entries}), 3)



if __name__ == "__main__":
    unittest.main()
