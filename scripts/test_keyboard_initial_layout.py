"""Regression guards for a visible, correctly sized keyboard on first focus."""
from pathlib import Path
import unittest

ROOT = Path(__file__).resolve().parent.parent
LAYOUT = ROOT / "SayboardKeyboard" / "Views" / "Layouts" / "AlphabeticKeyboardLayout.swift"
HOST = ROOT / "SayboardKeyboard" / "KeyboardViewController.swift"
ROOT_VIEW = ROOT / "SayboardKeyboard" / "Views" / "KeyboardView.swift"


class KeyboardInitialLayoutTests(unittest.TestCase):
    def test_letter_rows_remain_visible_and_rehydrate_on_reactivation(self):
        source = LAYOUT.read_text(encoding="utf-8")
        self.assertIn(".id(self.keyboardState.keyboardAppearanceRevision)", source)
        self.assertNotIn(".opacity(self.isCursorTracking ? 0.07 : 1)", source)
        self.assertNotIn(".allowsHitTesting(!self.isCursorTracking)", source)
        self.assertIn("self.firstKeyRow", source)
        self.assertIn("self.secondKeyRow", source)
        self.assertIn("self.thirdKeyRow", source)
        self.assertIn("@StateObject private var swipeTrail = SwipeTrailState()", source)
        self.assertIn("@ObservedObject var trail: SwipeTrailState", source)
        self.assertIn("onSwipePath: { path in self.swipeTrail.update(path) }", source)
        self.assertNotIn("@State private var liveSwipePath", source)

    def test_host_settings_before_swiftui_mount_and_heights_stay_in_sync(self):
        source = HOST.read_text(encoding="utf-8")
        appear = source.split("override func viewWillAppear(", 1)[1].split(
            "override func viewWillDisappear(", 1
        )[0]
        self.assertLess(appear.index("self.keyboardState.refresh()"),
                        appear.index("self.setupKeyboardView()"))
        self.assertLess(appear.index("self.syncFullAccessIfChanged()"),
                        appear.index("self.setupKeyboardView()"))
        self.assertIn("kind: self.keyboardState.effectiveTypingKind", source)
        self.assertIn("self.hostingHeightConstraint, height.constant != target", source)
        self.assertIn("override func viewDidLayoutSubviews()", source)

    def test_one_effective_keyboard_route_and_one_expanded_lookup(self):
        root = ROOT_VIEW.read_text(encoding="utf-8")
        self.assertEqual(root.count("AlphabeticKeyboardLayout(proxy:"), 1)
        self.assertIn("switch self.keyboardState.effectiveTypingKind", root)
        self.assertNotIn("switch self.keyboardState.keyboardKind", root)
        layout = LAYOUT.read_text(encoding="utf-8")
        update = layout.split("private func updateCandidates()", 1)[1].split(
            "private func beginCursorTracking()", 1
        )[0]
        self.assertIn("let ranked = JyutpingDictionary.shared.candidates(", update)
        self.assertIn("for: prefix, limit: gridVisible ? 200 : 12", update)
        self.assertNotIn("for: prefix, limit: 200", update)


if __name__ == "__main__":
    unittest.main()
