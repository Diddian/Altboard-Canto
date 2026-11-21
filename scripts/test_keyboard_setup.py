"""Offline contracts for keyboard setup examples and language ownership."""
import importlib.util
import json
import pathlib
import unittest

ROOT = pathlib.Path(__file__).resolve().parent.parent
SPEC = importlib.util.spec_from_file_location(
    "keyboard_setup_shapes", ROOT / "scripts/build-chinese-shapes.py"
)
SHAPES = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(SHAPES)


class KeyboardSetupTests(unittest.TestCase):
    def test_tutorial_shape_codes_exist_in_both_generations(self):
        source = ROOT / "scripts/data/chinese-shapes"
        for method, code in [("quick", "of"), ("cangjie", "onf")]:
            for generation in (3, 5):
                name = f"{method}{generation}"
                rows = SHAPES.parse_table(SHAPES.download(name, source_directory=source), name)
                self.assertIn((code, "你"), {(key, word) for key, word, _ in rows})
        rows = SHAPES.parse_table(SHAPES.download("stroke5", source_directory=source), "stroke5")
        self.assertIn((",/,n/", "你"), {(key, word) for key, word, _ in rows})

    def test_typing_consumers_do_not_follow_speech_language_changes(self):
        layout = (ROOT / "SayboardKeyboard/Views/Layouts/AlphabeticKeyboardLayout.swift").read_text()
        self.assertNotIn("SharedSettings().preferredSpokenLanguages", layout)
        self.assertIn('preferredTypingLanguages.contains("yue")', layout)
        self.assertIn("for: SharedSettings().preferredTypingLanguages", layout)
        self.assertIn("let preferred = SharedSettings().preferredTypingLanguages", layout)
        self.assertIn(".onChange(of: SharedSettings().preferredTypingLanguages)", layout)
        swipe = (ROOT / "SayboardKeyboard/Views/AlphabeticTouchRow.swift").read_text()
        self.assertIn("SharedSettings().preferredTypingLanguages", swipe)
        self.assertNotIn("SharedSettings().preferredSpokenLanguages", swipe)
        voice = (ROOT / "Sayboard/Views/Onboarding/OnboardingLanguagesView.swift").read_text()
        self.assertIn("settings.preferredSpokenLanguages = self.draft.languages", voice)
        self.assertNotIn("settings.preferredTypingLanguages = self.draft.languages", voice)

    def test_setup_messages_have_real_core_language_translations(self):
        catalog = json.loads((ROOT / "Shared/KeyboardSetup.xcstrings").read_text())
        self.assertEqual(catalog["sourceLanguage"], "en")
        for key, entry in catalog["strings"].items():
            for language in ("en", "zh-Hant", "de"):
                unit = entry["localizations"][language]["stringUnit"]
                self.assertEqual(unit["state"], "translated")
                self.assertTrue(unit["value"], (key, language))
        for key in ("Start typing without a download", "Use this method", "Typing languages"):
            self.assertNotEqual(catalog["strings"][key]["localizations"]["zh-Hant"]["stringUnit"]["value"], key)

    def test_probe_is_bounded_and_diagnostics_never_receive_its_text(self):
        view = (ROOT / "Sayboard/Views/Onboarding/OnboardingInputMethodView.swift").read_text()
        self.assertIn("String(self.response.prefix(32))", view)
        for line in view.splitlines():
            if "FeatureDiagnostics.record" in line:
                self.assertNotIn("response", line)
        self.assertNotIn("forKey: self.response", view)
        self.assertNotIn("set(self.response", view)


if __name__ == "__main__":
    unittest.main()
