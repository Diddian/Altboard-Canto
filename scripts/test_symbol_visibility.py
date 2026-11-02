"""Source regression for the symbol-key labels lost in IPA #64/#66.

This does NOT replace screenshot/device testing. It protects the rendering
choice and all 10/10/5 keys from accidental empty SwiftUI GlyphPath shapes.
"""
import json
import pathlib
import unittest

ROOT = pathlib.Path(__file__).resolve().parent.parent
KEY_BUTTON = ROOT / "SayboardKeyboard" / "Views" / "KeyButton.swift"
ALPHABET = ROOT / "SayboardKeyboard" / "Views" / "Layouts" / "AlphabeticKeyboardLayout.swift"
EXTENDED = ROOT / "SayboardKeyboard" / "Views" / "Layouts" / "ExtendedKeyboardLayout.swift"

def row(source: str, name: str) -> list[str]:
    prefix = f"private static let {name} = "
    found = [line.strip().split(prefix, 1)[1] for line in source.splitlines() if prefix in line]
    if len(found) != 1:
        raise AssertionError(f"Expected one declared {name}, got {len(found)}")
    return json.loads(found[0])


class SymbolVisibilityTests(unittest.TestCase):
    def test_key_label_and_callout_use_font_fallback(self):
        code = KEY_BUTTON.read_text()
        self.assertGreaterEqual(code.count("Text(verbatim: symbol)"), 2)
        self.assertNotIn("GlyphPath.canRender(symbol)", code)
        self.assertIn("self.symbolText(symbol, fontSize: fontSize)", code)
        self.assertIn("self.calloutSymbolText(symbol, fontSize: fontSize)", code)

    def test_alphabetic_number_symbol_rows_have_nonempty_labels(self):
        src = ALPHABET.read_text()
        for name in (
            "numbersRow1", "numbersRow2", "symbolsRow1", "symbolsRow2",
            "chineseNumbersRow2", "chineseSymbolsRow1", "chineseSymbolsRow2"
        ):
            with self.subTest(name=name):
                chars = row(src, name)
                self.assertEqual(len(chars), 10)
                self.assertTrue(all(chars))
        for c in ("「", "」", "『", "』", "《", "》", "【", "】", "。", "，", "？", "！"):
            with self.subTest(glyph=c):
                self.assertIn(c, src)
        self.assertIn("self.characterRow(", src)

    def test_extended_number_symbol_punctuation_rows(self):
        src = EXTENDED.read_text()
        for name in ("numbersRow1", "numbersRow2", "symbolsRow1", "symbolsRow2"):
            with self.subTest(name=name):
                self.assertEqual(len(row(src, name)), 10)
        self.assertEqual(len(row(src, "punctRow")), 5)
        self.assertIn("self.calloutKey(char: char", src)
        self.assertIn("content: .symbol(char)", src)


if __name__ == "__main__":
    unittest.main()
