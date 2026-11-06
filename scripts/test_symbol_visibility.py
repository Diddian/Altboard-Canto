"""Source regression for the symbol-key labels lost in IPA #64/#66.

This does NOT replace screenshot/device testing. It protects the rendering
choice and all 10/10/5 keys from accidental empty SwiftUI GlyphPath shapes.
"""
import json
import pathlib
import re
import unittest
import subprocess
import tempfile

ROOT = pathlib.Path(__file__).resolve().parent.parent
KEY_BUTTON = ROOT / "SayboardKeyboard" / "Views" / "KeyButton.swift"
ALPHABET = ROOT / "SayboardKeyboard" / "Views" / "Layouts" / "AlphabeticKeyboardLayout.swift"
EXTENDED = ROOT / "SayboardKeyboard" / "Views" / "Layouts" / "ExtendedKeyboardLayout.swift"

def row(source: str, name: str) -> list[str]:
    # Swift allows either "let row = [...]" or "let row: [String] = [...]".
    # ExtendedKeyboardLayout deliberately uses the typed form; the previous
    # parser rejected every typed declaration and blocked the IPA before Xcode.
    pattern = (
        r"^[ \t]*private static let " + re.escape(name)
        + r"(?:[ \t]*:[ \t]*\[String\])?[ \t]*=[ \t]*(\[[^\r\n]*\])[ \t]*$"
    )
    found = re.findall(pattern, source, flags=re.MULTILINE)
    if len(found) != 1:
        raise AssertionError(f"Expected one declared {name}, got {len(found)}")
    return json.loads(found[0])


class SymbolVisibilityTests(unittest.TestCase):
    def test_accepts_typed_and_untyped_swift_constant_rows(self):
        untyped = 'private static let probe = ["1", "2"]'
        typed = 'private static let probe: [String] = ["1", "2"]'
        self.assertEqual(row(untyped, "probe"), ["1", "2"])
        self.assertEqual(row(typed, "probe"), ["1", "2"])

    def test_key_label_and_callout_use_font_fallback(self):
        code = KEY_BUTTON.read_text()
        self.assertGreaterEqual(code.count("Text(verbatim: symbol)"), 2)
        self.assertNotIn("GlyphPath.canRender(symbol)", code)
        self.assertIn("self.symbolText(symbol, fontSize: fontSize)", code)
        self.assertIn("self.calloutSymbolText(symbol, fontSize: fontSize)", code)

    def test_alphabetic_number_symbol_rows_have_nonempty_labels(self):
        src = ALPHABET.read_text()
        for name in ("numbersRow1", "numbersRow2", "symbolsRow1", "symbolsRow2"):
            with self.subTest(name=name):
                chars = row(src, name)
                self.assertEqual(len(chars), 10)
                self.assertTrue(all(chars))
        self.assertEqual(row(src, "symbolsRow1"),
                         ["[", "]", "{", "}", "#", "%", "^", "*", "+", "="])
        self.assertEqual(row(src, "symbolsRow2"),
                         ["_", "\\", "|", "~", "<", ">", "€", "£", "¥", "•"])
        self.assertIn("self.characterRow(Self.symbolsRow1, chineseAlternates: self.isChineseSymbolsPage)", src)
        self.assertIn("self.characterRow(Self.symbolsRow2, chineseAlternates: self.isChineseSymbolsPage)", src)
        self.assertIn("case .numbers: self.characterRow(Self.numbersRow2,", src)
        self.assertIn("chineseAlternates: self.usesChinesePunctuation", src)
        self.assertIn("self.page == .symbols && self.usesChinesePunctuation", src)
        self.assertIn('["。", "，", "？", "！", self.smartChineseQuote]', src)
        self.assertNotIn("chineseSymbolsRow1", src)
        self.assertNotIn("chineseSymbolsRow2", src)

    def test_cantonese_long_press_has_distinct_choices(self):
        shared = (ROOT / "Shared" / "LetterKeyAlternates.swift").read_text()
        hold = (ROOT / "SayboardKeyboard" / "Views" / "SymbolHoldKey.swift").read_text()
        self.assertIn("private static let chineseVariants:", shared)
        for glyph in ("「", "」", "『", "』", "《", "》", "【", "】", "〔", "〕"):
            self.assertIn(glyph, shared)
        self.assertIn("var chineseAlternates = false", hold)
        self.assertIn("choices(for: self.symbol, chinese: self.chineseAlternates)", hold)
        self.assertIn("let index = self.expandsLeft ? self.options.count - 1 - position : position", hold)
        self.assertIn("Text(verbatim: self.face ?? self.symbol)", hold)

    def test_symbol_alternates_match_130_and_do_not_affect_latin(self):
        fixture = r"""
import Foundation
@main struct SymbolFixture {
    static func main() {
        let latin = SymbolKeyAlternates.choices(for: "[")
        assert(latin.first == "[")
        assert(!latin.contains("「"))
        let chinese = SymbolKeyAlternates.choices(for: "[", chinese: true)
        assert(chinese.first == "[")
        assert(chinese.contains("「") && chinese.contains("『"))
        assert(chinese.count <= 8)
        assert(Set(chinese).count == chinese.count)
        let quotes = SymbolKeyAlternates.choices(for: "\"", chinese: true)
        assert(quotes.contains("「") && quotes.contains("」"))
        assert(SymbolKeyAlternates.choices(for: "1").first == "1")
    }
}
"""
        with tempfile.TemporaryDirectory(prefix="altboard-symbol-") as temp:
            target = pathlib.Path(temp)
            swift_file = target / "Fixture.swift"
            swift_file.write_text(fixture, encoding="utf-8")
            output = target / "check"
            compiled = subprocess.run(
                ["swiftc", "-o", str(output),
                 str(ROOT / "Shared" / "LetterKeyAlternates.swift"), str(swift_file)],
                capture_output=True, text=True, timeout=90, check=False,
            )
            self.assertEqual(compiled.returncode, 0, compiled.stdout + compiled.stderr)
            executed = subprocess.run([str(output)], capture_output=True,
                                      text=True, timeout=30, check=False)
            self.assertEqual(executed.returncode, 0, executed.stdout + executed.stderr)

    def test_extended_number_symbol_punctuation_rows(self):
        src = EXTENDED.read_text()
        for name in ("numbersRow1", "numbersRow2", "symbolsRow1", "symbolsRow2"):
            with self.subTest(name=name):
                self.assertEqual(len(row(src, name)), 10)
        self.assertEqual(len(row(src, "punctRow")), 5)
        self.assertIn("self.calloutKey(char: char", src)
        self.assertIn("SymbolHoldKey(symbol: char", src)


if __name__ == "__main__":
    unittest.main()
