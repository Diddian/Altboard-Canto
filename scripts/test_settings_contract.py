"""Source-level contracts for #84-based host settings and data operations."""
from pathlib import Path
import unittest
from test_keyboard_initial_layout import git_blob

ROOT = Path(__file__).resolve().parent.parent
def read(path): return (ROOT / path).read_text(encoding="utf-8")

class SettingsContractTests(unittest.TestCase):
    def test_settings_follow_user_tasks(self):
        s = read("Sayboard/Views/SettingsView.swift")
        for t in ('Section("Speech & AI")', 'Text("App")',
                  "SpeechLanguagesSettingsView(inline: true)",
                  "DictationSettingsView(inline: true)",
                  "LLMSettingsView(inline: true)",
                  "KeyboardSettingsView(", "DataAndStorageSettingsView(inline: true)",
                  "LLMModelsScreen()", "AppLanguageListView()", "DiagnosticsView()"):
            self.assertIn(t, s)
    def test_inline_actions_and_test_field_clear(self):
        self.assertIn("ActiveSessionToggle()", read("Sayboard/Views/SettingsView.swift"))
        self.assertIn("VoiceOutputSettingsView(inline: true)",
                      read("Sayboard/Views/SettingsNavigationViews.swift"))
    def test_sections_with_footers_use_explicit_headers(self):
        home=read("Sayboard/Views/SettingsView.swift")
        self.assertIn('Section("Speech & AI")', home)
        self.assertIn('Label("History & Storage"', home)
    def test_keyboard_options_are_not_a_flat_settings_page(self):
        self.assertIn("KeyboardSettingsView(selectedKind:",
                      read("Sayboard/Views/SettingsView.swift"))
    def test_settings_routes_have_single_owners(self):
        s=read("Sayboard/Views/SettingsView.swift")
        self.assertEqual(s.count("ActiveSessionToggle()"), 1)
        self.assertEqual(s.count("LLMModelsScreen()"), 1)
    def test_native_emoji_switcher_and_opt_in_top_globe(self):
        self.assertEqual(git_blob("SayboardKeyboard/Views/NativeInputModeSwitchKey.swift"),
                         "5401597201bed836e6e13ae07bb172f3a28dfe99")
    def test_output_and_formatting_have_one_owner(self):
        self.assertIn("TextOutputSection(inline: true)",
                      read("Sayboard/Views/LLMSettingsView.swift"))
    def test_no_custom_swipe_to_switch_app_tabs(self):
        s=read("Sayboard/Views/MainTabView.swift")
        self.assertIn("case meetings",s)
        self.assertNotIn(".simultaneousGesture(",s)
    def test_host_keeps_render_tree_across_focus_changes(self):
        self.assertEqual(git_blob("SayboardKeyboard/KeyboardViewController.swift"),
                         "ae3e1e67e43859f3d339c27b5941d7cbed4ad2a5")
    def test_meeting_tab_uses_existing_local_recorder(self):
        s=read("Sayboard/Views/MeetingRecordsView.swift")
        self.assertIn("MeetingRecordingCoordinator.shared",s)
        self.assertIn("updateRecord(id:",s)
        self.assertIn("deleteRecord(id:",s)
    def test_live_default_uses_model_and_memory_and_retains_explicit_choice(self):
        s=read("Shared/SharedSettings.swift")
        self.assertIn("var experimentalLiveDictationEnabled:",s)
        self.assertIn("defaults.object(forKey: SharedKey.experimentalLiveDictationEnabled)",s)
    def test_history_only_deletes_voice_notes(self):
        h=read("Shared/HistoryStore.swift")
        self.assertIn("guard self.writeRecords",h)
        self.assertNotIn('appendingPathComponent("meetings")',h)
    def test_user_initiated_export_includes_explicit_corrections(self):
        s=read("Sayboard/Services/LocalUserDataStore.swift")
        self.assertIn("static func export(",s)
        self.assertIn("PersonalVocabularyExport.encode(",s)
        self.assertIn("guard !self.recordingActive",read("Sayboard/Views/DataAndStorageSettingsView.swift"))
    def test_universal_cantonese_diagnostics_preserved(self):
        s=read("SayboardKeyboard/JyutpingDictionary.swift")
        self.assertIn("canto.ime.schemePreferenceCounts.v1",s)
        self.assertIn("canto.jyutping.selectionCounts",s)
    def test_explicit_unknown_word_learning_remains(self):
        self.assertEqual(git_blob("SayboardKeyboard/JyutpingDictionary.swift"),
                         "b9deb2139b9c629bc105fd5a1ee2ffaab65fb155")
        p=read("Sayboard/Services/PermissionService.swift")
        self.assertNotIn("canto.keyboardOpenedAtLeastOnce", p.split("static func isKeyboardAddedSync()",1)[1].split("private static func installedExtensionIdentifiers()",1)[0])

if __name__ == "__main__":
    unittest.main()
