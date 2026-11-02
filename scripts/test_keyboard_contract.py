"""Static regression contracts for already reviewed keyboard interaction ownership.

This is not an iPhone double-tap test. It guards against accidental additional
gesture layers and old settings references while preserving VoiceOver behavior.
"""
import pathlib
import unittest

ROOT = pathlib.Path(__file__).resolve().parent.parent


class KeyboardInteractionContracts(unittest.TestCase):
    def source(self, name):
        return (ROOT / name).read_text(encoding="utf-8")

    def test_UIKit_owns_physical_alphabet_touches_once(self):
        source = self.source("SayboardKeyboard/Views/AlphabeticTouchRow.swift")
        self.assertEqual(source.count("private struct ImmediateKeyTouchSurface:"), 1)
        self.assertEqual(source.count("private final class ImmediateKeyTouchView:"), 1)
        for token in ("touchesBegan(", "touchesMoved(", "touchesEnded(", "touchesCancelled("):
            self.assertEqual(source.count("override func " + token), 1, token)
        self.assertIn(".accessibilityHidden(true)", source)
        self.assertIn(".accessibilityAction {", source)
        self.assertNotIn(".simultaneousGesture(", source)
        self.assertNotIn(".highPriorityGesture(", source)
        self.assertIn("self.onInsert(output)", source)

    def test_legacy_scheme_no_longer_called_by_live_keyboard(self):
        source = self.source("SayboardKeyboard/Views/Layouts/AlphabeticKeyboardLayout.swift")
        self.assertNotIn("self.romanization", source)
        self.assertNotIn("romanizationRaw", source)
        self.assertIn("JyutpingDictionary.shared.candidates(for: prefix)", source)
        self.assertIn("ChinesePunctuationPolicy.nextCornerQuote(after: context)", source)

    def test_resources_have_only_one_name_and_keep_extension_resources(self):
        source = self.source("project.yml")
        for directory in ("JyutpingResources", "EmojiResources"):
            self.assertIn(f"- path: {directory}\n        buildPhase: resources\n        excludes:\n          - .gitkeep", source)
        self.assertIn("PRODUCT_BUNDLE_IDENTIFIER: app.sayboard.keyboard", source)

    def test_QA_branch_is_not_in_unsigned_release_workflow(self):
        flow = self.source(".github/workflows/build-unsigned-ipa.yml")
        self.assertNotIn("review/qa-half-wave1-20261102", flow)
        self.assertIn("altboard-canto-swipe-beta", flow)
        self.assertIn("upload-artifact", flow)


if __name__ == "__main__":
    unittest.main()
