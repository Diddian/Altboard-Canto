"""Regression checks for supported interface locale catalogs."""
import json
import re
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent

def catalog(path):
    return json.loads((ROOT / path).read_text(encoding="utf-8"))

def string_units(entry):
    if "stringUnit" in entry:
        yield entry["stringUnit"]
    for cases in entry.get("variations", {}).values():
        for case in cases.values():
            yield from string_units(case)

class InterfaceLocalizationTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        selector = (ROOT / "Sayboard/Views/AppLanguageListView.swift").read_text(encoding="utf-8")
        cls.app_codes = set(re.findall(r'InterfaceLanguage\(code: "([^"]+)"', selector))
        cls.locales = (cls.app_codes - {"en", "no"}) | {"nb"}
        cls.catalogs = [
            catalog("Sayboard/Localizable.xcstrings"),
            catalog("SayboardKeyboard/Localizable.xcstrings"),
            catalog("Sayboard/InfoPlist.xcstrings"),
            catalog("SayboardKeyboard/InfoPlist.xcstrings"),
        ]

    def test_every_advertised_language_has_a_catalog(self):
        self.assertIn("zh-Hant", self.app_codes)
        self.assertIn("zh-Hans", self.app_codes)
        self.assertNotIn("zh", self.app_codes)
        self.assertIn("no", self.app_codes)
        self.assertEqual(len(self.locales), 30)
        for bundle in self.catalogs:
            self.assertEqual(bundle["sourceLanguage"], "en")
            self.assertTrue(bundle["strings"])
            for key, entry in bundle["strings"].items():
                locales = set(entry.get("localizations", {})) - {"en"}
                self.assertEqual(locales, self.locales, f"Missing locale for {key!r}")
                for locale, translation in entry["localizations"].items():
                    if locale == "en":
                        continue  # Source-language strings are supplied by the English key.
                    units = list(string_units(translation))
                    self.assertTrue(units, f"No translation units for {locale} {key}")
                    for unit in units:
                        self.assertEqual(unit.get("state"), "translated", f"{locale} {key}")
                        self.assertNotEqual(unit.get("value"), "", f"{locale} {key}")

    def test_main_catalog_retains_existing_strings(self):
        self.assertGreaterEqual(len(self.catalogs[0]["strings"]), 380)
        self.assertIn("%lld words left", self.catalogs[0]["strings"])
        self.assertIn(" ", self.catalogs[0]["strings"])
        self.assertIn("Full Access", self.catalogs[0]["strings"])

    def test_chinese_scripts_have_distinct_real_translations(self):
        for bundle, key in [
            (self.catalogs[0], "Settings"),
            (self.catalogs[0], "Keyboard"),
            (self.catalogs[1], "Add punctuation"),
            (self.catalogs[1], "No speech recognized. Try speaking again"),
            (self.catalogs[2], "NSMicrophoneUsageDescription"),
        ]:
            self.assertIn(key, bundle["strings"])
            entries = bundle["strings"][key]["localizations"]
            self.assertNotEqual(
                entries["zh-Hant"]["stringUnit"]["value"],
                entries["zh-Hans"]["stringUnit"]["value"],
                f"Expected different Chinese wording for {key}",
            )

    def test_locale_routing_and_legacy_migration(self):
        code = (ROOT / "Shared/Constants.swift").read_text(encoding="utf-8")
        root = (ROOT / "Sayboard/SayboardApp.swift").read_text(encoding="utf-8")
        self.assertIn('static func migratedStoredLanguage(_ code: String)', code)
        self.assertIn('if code == "zh" { return "zh-Hans" }', code)
        self.assertIn('if components.contains("hans") { return "zh-Hans" }', code)
        self.assertIn('if components.contains("hant") { return "zh-Hant" }', code)
        self.assertIn('if components.first == "yue" { return "zh-Hant" }', code)
        self.assertIn("AppLanguageConfig.migratedStoredLanguage(current)", root)
        self.assertIn('self.appLanguage == "no" ? "nb" : self.appLanguage', root)

    def test_core_navigation_is_localized_but_diagnostics_remains_english(self):
        strings = self.catalogs[0]["strings"]
        for key in (
            "Settings", "History", "Meetings", "App Language",
            "Keyboard", "Speech & AI", "Speech Model", "Text Model",
            "Dictation", "AI Actions", "History & Storage",
            "Setup & Permissions", "Haptic Feedback", "Output Language",
            "Language Priority", "Free Dictation", "No recordings yet",
        ):
            self.assertIn(key, strings)
        self.assertNotIn("Diagnostics", strings)

if __name__ == "__main__":
    unittest.main()
