#!/usr/bin/env python3
"""Static QA for settings contracts; does not modify user defaults."""
import pathlib
import unittest

ROOT = pathlib.Path(__file__).resolve().parent.parent

class SettingsContractTests(unittest.TestCase):
    def test_legacy_romanization_picker_not_reintroduced(self):
        content = (ROOT / "Sayboard" / "Views" / "KeyboardSettingsView.swift").read_text()
        self.assertNotIn('Picker("Cantonese Romanization"', content)
        self.assertIn('Toggle("Swipe Typing (English / German)"', content)

    def test_haptic_reset_default_and_feedback_controls_exist(self):
        content = (ROOT / "Sayboard" / "Views" / "KeyboardSettingsView.swift").read_text()
        settings = (ROOT / "Shared" / "SharedSettings.swift").read_text()
        self.assertIn('Button("Reset to Default (55%)")', content)
        self.assertIn('Button("Test Haptic")', content)
        self.assertIn("static let defaultKeyboardHapticStrength: Double = 0.55", settings)
        self.assertIn("min(1.0, max(0.15, newValue))", settings)

    def test_settings_keyboard_sections_are_consolidated(self):
        keyboard = (ROOT / "Sayboard" / "Views" / "KeyboardSettingsView.swift").read_text()
        speech = (ROOT / "Sayboard" / "Views" / "SpeechLanguagesSettingsView.swift").read_text()
        voice = (ROOT / "Sayboard" / "Views" / "VoiceOutputSettingsView.swift").read_text()
        home = (ROOT / "Sayboard" / "Views" / "SettingsView.swift").read_text()
        self.assertIn('Text("Keyboard")', keyboard)
        for obsolete in ('Section("Touch Learning")', 'Section("Feedback")',
                         'Section("Typing Shortcuts")', 'Text("Keyboard Preview")'):
            self.assertNotIn(obsolete, keyboard)
        self.assertIn('KeyboardTestPreview(', keyboard)
        self.assertIn('Toggle("Double-Space Period"', keyboard)
        self.assertIn('CantoneseCorrectionsView()', keyboard)
        self.assertIn('preferredSpokenLanguages.contains("yue")', keyboard)
        self.assertNotIn('CantoneseCorrectionsView()', voice)
        self.assertIn('onPreferredLanguagesChanged', speech)
        self.assertIn('cantoneseSelected: self.preferredSpokenLanguages.contains("yue")', home)

    def test_active_session_header_note_is_always_visible(self):
        content = (ROOT / "Sayboard" / "Views" / "SettingsNavigationViews.swift").read_text()
        self.assertIn('Text("When active,")', content)
        self.assertIn('Image(systemName: "mic.fill")', content)
        self.assertIn('Text("will appear")', content)
        self.assertNotIn('NavigationLink("Active Session Info")', content)

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
