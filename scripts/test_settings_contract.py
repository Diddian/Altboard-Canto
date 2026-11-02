#!/usr/bin/env python3
"""Static QA for settings contracts; does not modify user defaults."""
import pathlib
import unittest

ROOT = pathlib.Path(__file__).resolve().parent.parent

class SettingsContractTests(unittest.TestCase):
    def test_legacy_romanization_picker_not_reintroduced(self):
        content = (ROOT / "Sayboard" / "Views" / "KeyboardSettingsView.swift").read_text()
        self.assertNotIn('Picker("Cantonese Romanization"', content)
        self.assertIn("Sidney Lau, Yale and Jyutping", content)
        self.assertIn('Toggle("Swipe Typing (English / German · Beta)"', content)

    def test_haptic_reset_default_and_feedback_controls_exist(self):
        content = (ROOT / "Sayboard" / "Views" / "KeyboardSettingsView.swift").read_text()
        settings = (ROOT / "Shared" / "SharedSettings.swift").read_text()
        self.assertIn('Button("Reset to Default (55%)")', content)
        self.assertIn('Button("Test Haptic")', content)
        self.assertIn("static let defaultKeyboardHapticStrength: Double = 0.55", settings)
        self.assertIn("min(1.0, max(0.15, newValue))", settings)

    def test_visibility_and_legacy_settings_stay_backward_compatible(self):
        settings = (ROOT / "Shared" / "SharedSettings.swift").read_text()
        kind = (ROOT / "Shared" / "KeyboardKind.swift").read_text()
        self.assertIn("var keyboardShowSettingsKey: Bool", settings)
        self.assertIn("var keyboardRomanizationScheme: CantoneseRomanizationScheme", settings)
        self.assertIn("case jyutping", kind)
        self.assertIn("case yale", kind)
        self.assertIn("case yuetyam", kind)

if __name__ == "__main__":
    unittest.main()
