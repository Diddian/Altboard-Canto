"""Validate host localization without changing the #84 keyboard catalogs."""
import json
import re
import unittest
from pathlib import Path
from test_keyboard_initial_layout import git_blob

ROOT = Path(__file__).resolve().parent.parent
def catalog(path):
    return json.loads((ROOT / path).read_text(encoding="utf-8"))

class InterfaceLocalizationTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        s=(ROOT / "Sayboard/Views/AppLanguageListView.swift").read_text()
        cls.codes=set(re.findall(r'InterfaceLanguage\(code: "([^"]+)"', s))
        cls.locales=(cls.codes - {"en", "no"}) | {"nb"}
        cls.app=catalog("Sayboard/Localizable.xcstrings")
        cls.info=catalog("Sayboard/InfoPlist.xcstrings")
    def test_every_advertised_language_has_a_catalog(self):
        self.assertEqual(len(self.codes),31)
        self.assertEqual(len(self.locales),30)
        self.assertIn("zh-Hant",self.codes)
        self.assertIn("zh-Hans",self.codes)
        for c in [self.app,self.info]:
            self.assertEqual(c["sourceLanguage"],"en")
            for entry in c["strings"].values():
                self.assertTrue(self.locales.issubset(set(entry.get("localizations",{}))))
    def test_main_catalog_retains_existing_strings(self):
        self.assertGreaterEqual(len(self.app["strings"]),380)
        for key in ("Full Access","Speech Model","Text Model","History & Storage","App Language"):
            self.assertIn(key,self.app["strings"])
    def test_chinese_scripts_have_distinct_real_translations(self):
        s=self.app["strings"]
        different=0
        for entry in s.values():
            translations=entry.get("localizations",{})
            a=translations.get("zh-Hant",{}).get("stringUnit",{}).get("value")
            b=translations.get("zh-Hans",{}).get("stringUnit",{}).get("value")
            if a and b and a!=b: different+=1
        self.assertGreater(different,20)
    def test_locale_routing_and_legacy_migration(self):
        s=(ROOT/"Shared/Constants.swift").read_text()
        self.assertIn("static func migratedStoredLanguage",s)
        self.assertIn('if code == "zh" { return "zh-Hans" }',s)
        root=(ROOT/"Sayboard/SayboardApp.swift").read_text()
        self.assertIn("AppLanguageConfig.migratedStoredLanguage",root)
    def test_core_navigation_is_localized_but_diagnostics_remains_english(self):
        self.assertEqual(git_blob("SayboardKeyboard/Localizable.xcstrings"),
                         "24f5d1d1562bad36e8d1a8553ba164b11d2680d5")
        self.assertIn("History & Storage",self.app["strings"])
        self.assertIn("NSMicrophoneUsageDescription",self.info["strings"])

if __name__=="__main__":
    unittest.main()
