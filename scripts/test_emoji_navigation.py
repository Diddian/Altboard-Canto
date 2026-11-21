"""Source contracts for local Emoji navigation and native keyboard switching."""
from pathlib import Path
import re
import unittest

ROOT = Path(__file__).resolve().parent.parent


def source(path):
    return (ROOT / path).read_text(encoding="utf-8")


def function(text, name):
    body = text.split(f"private func {name}(", 1)[1]
    return re.split(r"\n  (?:private |@discardableResult)", body, maxsplit=1)[0]


class EmojiNavigationTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.chrome = source("SayboardKeyboard/Views/Layouts/KeyboardChrome.swift")
        cls.layout = source("SayboardKeyboard/Views/Layouts/AlphabeticKeyboardLayout.swift")
        cls.emoji = source("SayboardKeyboard/Views/EmojiKeyboardView.swift")

    def test_smiley_routes_to_local_page_without_system_switch(self):
        bottom = self.chrome.split("struct KeyboardBottomRow:", 1)[1]
        self.assertIn("if let openEmoji = self.onEmojiAction", bottom)
        emoji = bottom.split("if let openEmoji = self.onEmojiAction", 1)[1].split(
            "} else if self.keyboardState.showsGlobeButton", 1
        )[0]
        self.assertIn("content: .nativeEmojiGlyph", emoji)
        self.assertEqual(emoji.count("openEmoji()"), 1)
        self.assertNotIn("NativeInputModeSwitchKey", emoji)
        self.assertNotIn("advanceToNextInputMode", emoji)
        self.assertIn('.accessibilityLabel("Emoji")', emoji)
        self.assertIn("onEmojiAction: { self.openEmojiPage() }", self.layout)
        self.assertIn("self.showsEmojiPage = true", function(self.layout, "openEmojiPage"))
        self.assertIn("if self.showsEmojiPage {\n        EmojiKeyboardView(", self.layout)

    def test_abc_numbers_and_close_have_explicit_destinations(self):
        self.assertIn("onAlphabet: { self.closeEmojiPage(returningTo: .letters) }", self.layout)
        self.assertIn("onNumbers: { self.closeEmojiPage(returningTo: .numbers) }", self.layout)
        self.assertIn("onClose: { self.closeEmojiPage(returningTo: self.emojiReturnPage) }", self.layout)
        close = function(self.layout, "closeEmojiPage")
        self.assertIn("self.showsEmojiPage = false", close)
        self.assertIn("self.page = page", close)
        self.assertIn("self.updateCandidates()", close)

    def test_opening_emoji_preserves_pending_composition(self):
        opening = function(self.layout, "openEmojiPage")
        self.assertNotIn("self.clearComposition()", opening)
        self.assertNotIn("self.clearShapeComposition()", opening)
        self.assertNotIn("self.proxy.insertText", opening)
        self.assertNotIn("self.proxy.deleteBackward", opening)
        self.assertIn("self.cantoneseRefreshTask?.cancel()", opening)
        self.assertIn("self.latinRefreshTask?.cancel()", opening)

    def test_selection_has_one_insertion_owner_and_no_implicit_candidate(self):
        self.assertIn("onInsertEmoji: { self.insertEmoji($0) }", self.layout)
        self.assertEqual(self.emoji.count("self.onInsertEmoji(choice)"), 1)
        self.assertNotIn("self.proxy.insertText(choice)", self.emoji)
        insertion = function(self.layout, "insertEmoji")
        self.assertEqual(insertion.count("self.proxy.insertText(emoji)"), 1)
        self.assertNotIn("self.proxy.deleteBackward", insertion)
        self.assertNotIn("self.choose(", insertion)
        self.assertNotIn("self.chooseShape(", insertion)
        self.assertIn("epoch == self.keyboardState.documentEpoch", insertion)
        self.assertIn("self.shapeHostAnchor = self.proxy.documentContextBeforeInput()", insertion)

    def test_native_globe_remains_available_inside_emoji(self):
        toolbar = self.emoji.split("private var searchToolbar:", 1)[1].split(
            "private var searchKeypad:", 1
        )[0]
        self.assertIn("self.keyboardState.needsInputModeSwitchKey || self.keyboardState.showGlobeKey", toolbar)
        self.assertEqual(toolbar.count("NativeInputModeSwitchKey("), 1)
        self.assertIn('iconName: "globe"', toolbar)
        self.assertIn("configure: self.keyboardState.configureInputModeListButton", toolbar)
        controller = source("SayboardKeyboard/KeyboardViewController.swift")
        self.assertIn("#selector(handleInputModeList(from:with:))", controller)
        self.assertIn("for: .allTouchEvents", controller)

    def test_search_space_and_delete_stay_out_of_host_text(self):
        self.assertIn('KeyButton(content: .text("Space"))', self.emoji)
        space = self.emoji.split('KeyButton(content: .text("Space"))', 1)[1].split(
            "} else {", 1
        )[0]
        self.assertIn('self.search += " "', space)
        self.assertNotIn("self.proxy", space)
        bottom = self.emoji.split("private var bottomRow:", 1)[1].split("/// Tapping", 1)[0]
        self.assertIn("if self.searchActive && !self.search.isEmpty", bottom)
        self.assertIn("} else if !self.searchActive {\n          self.proxy.deleteBackward()", bottom)
        self.assertIn('Text("No Emoji found")', self.emoji)
        self.assertIn('self.searchActive ? "Show Emoji results" : "Return"', bottom)

    def test_touch_accessibility_and_diagnostics_use_existing_owners(self):
        cell = self.emoji.split("private struct EmojiTouchCell:", 1)[1]
        self.assertEqual(cell.count("ImmediateKeyTouchSurface("), 1)
        self.assertIn("onCancelled: { self.cancel() }", cell)
        self.assertIn(".accessibilityAction {", cell)
        self.assertNotIn(".onTapGesture", cell)
        self.assertIn("FeatureDiagnostics.record(.keyboardEmoji, .selected)", self.emoji)
        self.assertIn("FeatureDiagnostics.record(.keyboardEmoji, .started)", self.layout)
        self.assertIn("FeatureDiagnostics.record(.keyboardEmoji, .completed)", self.layout)
        self.assertNotRegex(self.emoji, r"FeatureDiagnostics\.record\([^\n]*(?:choice|self\.search)")
        self.assertIn("let pages = self.pages", self.emoji)
        self.assertNotIn("self.pages[index].entries", self.emoji)

    def test_tone_drag_uses_rendered_geometry_and_keeps_all_variants(self):
        cell = self.emoji.split("private struct EmojiTouchCell:", 1)[1]
        self.assertIn("self.pickerGeometry.selection(", cell)
        self.assertIn("atX: Double(self.latestTouch.x), y: Double(self.latestTouch.y)", cell)
        self.assertNotIn("initialX", cell)
        self.assertNotIn("40.kbScaled -", cell)
        self.assertIn("pagerSize: geometry.size", self.emoji)
        self.assertIn(".offset(x: CGFloat(self.pickerGeometry.centerOffsetX)", cell)
        self.assertIn("y: CGFloat(self.pickerGeometry.originY)", cell)
        self.assertIn("ForEach(0..<geometry.rows", cell)
        self.assertIn("variants.count", cell)
        self.assertNotIn("self.variants.prefix", cell)
        self.assertIn(".accessibilityActions {", cell)
        self.assertIn("ForEach(self.variants)", cell)

    def test_tone_picker_releases_scroll_on_end_cancel_and_disappearance(self):
        self.assertIn("tonePickerCells = Set<String>()", self.emoji)
        self.assertIn('let id = "\\(index):\\(column)"', self.emoji)
        self.assertIn("self.tonePickerCells.insert(id)", self.emoji)
        self.assertIn("self.tonePickerCells.remove(id)", self.emoji)
        self.assertIn(".scrollDisabled(!self.tonePickerCells.isEmpty)", self.emoji)
        self.assertIn(".scrollClipDisabled()", self.emoji)
        cell = self.emoji.split("private struct EmojiTouchCell:", 1)[1]
        self.assertIn(".onDisappear { self.cancel() }", cell)
        self.assertIn("guard self.choosing != value else { return }", function(cell, "setChoosing"))
        self.assertIn("self.onChoosingChanged(value)", function(cell, "setChoosing"))
        self.assertIn("self.setChoosing(false)", function(cell, "cancel"))
        self.assertIn("self.cancel()", function(cell, "end"))
        begin = function(cell, "begin")
        self.assertLess(begin.index("Task.sleep"), begin.index("self.setChoosing(true)"))


if __name__ == "__main__":
    unittest.main()
