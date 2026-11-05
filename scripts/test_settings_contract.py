#!/usr/bin/env python3
"""Source-level contracts for user-facing settings and keyboard flows."""
from pathlib import Path
import unittest

ROOT = Path(__file__).resolve().parent.parent


def read(path):
    return (ROOT / path).read_text(encoding="utf-8")


class SettingsContractTests(unittest.TestCase):
    def test_settings_follow_user_tasks(self):
        home = read("Sayboard/Views/SettingsView.swift")
        for heading in ('Section("Start Here")', 'Section("Speech & AI")',
                        'Section("Keyboard")', 'Section("Your Data")',
                        'Text("App")'):
            self.assertIn(heading, home)
        for path in ("SpeechLanguagesSettingsView(", "DictationSettingsView()",
                     "VoiceOutputSettingsView()", "LLMSettingsView()",
                     "KeyboardSettingsView(", "DataAndStorageSettingsView()",
                     "AppLanguageListView()", "DiagnosticsView()"):
            self.assertIn(path, home)
        self.assertNotIn("DictationSettingsView(inline: true", home)
        self.assertIn("Altboard-Canto · Source on GitHub", home)

    def test_sections_with_footers_use_explicit_headers(self):
        sections = {
            "Sayboard/Views/SettingsView.swift": ("App",),
            "Sayboard/Views/SettingsNavigationViews.swift":
                ("Microphone & Recording", "Live Speech to Text"),
            "Sayboard/Views/KeyboardSettingsView.swift": ("Keyboard Layout",),
            "Sayboard/Views/KeyboardCustomizationView.swift":
                ("Haptic Feedback", "Keyboard Buttons"),
            "Sayboard/Views/DataAndStorageSettingsView.swift":
                ("Personal Vocabulary",),
            "Sayboard/Views/LearningDataSettingsView.swift":
                ("Learned Suggestions", "Your Data"),
        }
        for path, titles in sections.items():
            source = read(path)
            for title in titles:
                with self.subTest(path=path, section=title):
                    self.assertNotIn('Section("' + title + '") {', source)
                    self.assertIn('Text("' + title + '")', source)
                    self.assertIn('} header: {', source)
                    self.assertIn('} footer: {', source)

    def test_keyboard_options_are_not_a_flat_settings_page(self):
        layout = read("Sayboard/Views/KeyboardSettingsView.swift")
        custom = read("Sayboard/Views/KeyboardCustomizationView.swift")
        self.assertIn('Label("Keyboard Type"', layout)
        self.assertIn('Label("Key Order"', layout)
        self.assertIn('Text("German (Ä Ö Ü ß)")', layout)
        self.assertIn(".pickerStyle(.menu)", layout)
        self.assertIn("KeyboardTestPreview(", layout)
        self.assertIn("KeyboardCustomizationView()", layout)
        for control in ('Auto-capitalize Sentences', 'Double-Space Period',
                        'Haptic Feedback', 'Extra Globe Key', 'Settings Key',
                        'Output & Translation Key', 'Text AI Key'):
            self.assertIn(control, custom)
        self.assertIn('Text("Not yet available")', custom)

    def test_native_globe_is_optional_except_when_ios_requires_it(self):
        keyboard = read("SayboardKeyboard/Views/Layouts/KeyboardChrome.swift")
        state = read("SayboardKeyboard/KeyboardState.swift")
        config = read("Shared/SharedSettings.swift")
        self.assertIn("self.keyboardState.showGlobeKey || self.keyboardState.needsInputModeSwitchKey",
                      keyboard)
        self.assertIn("NativeInputModeSwitchKey(", keyboard)
        self.assertIn("var keyboardShowGlobeKey: Bool", config)
        self.assertIn("self.showGlobeKey = self.settings.keyboardShowGlobeKey", state)

    def test_first_focus_remounts_after_measured_size(self):
        controller = read("SayboardKeyboard/KeyboardViewController.swift")
        self.assertIn("rootNeedsMeasuredRemount", controller)
        self.assertIn("hostedView.bounds.width > 1", controller)
        self.assertIn("controller.rootView = KeyboardView(", controller)
        self.assertIn("keyboardAppearanceRevision &+= 1", controller)

    def test_meeting_tab_uses_existing_local_recorder(self):
        tabs = read("Sayboard/Views/MainTabView.swift")
        meeting = read("Sayboard/Views/MeetingRecordsView.swift")
        recording = read("Sayboard/Services/MeetingRecordingCoordinator.swift")
        self.assertIn('Tab("Meetings"', tabs)
        self.assertNotIn('Tab("Models"', tabs)
        self.assertIn('Image(systemName: "square.and.pencil")', meeting)
        self.assertIn(".searchable(", meeting)
        self.assertIn('Image(systemName: "gobackward.15")', meeting)
        self.assertIn('Image(systemName: "goforward.15")', meeting)
        self.assertIn("MeetingAudioPlayback()", meeting)
        self.assertIn("sequenceNumber", recording)
        self.assertIn("static let partDuration: TimeInterval = 15 * 60", recording)
        self.assertIn("static let updateSeconds = 8", recording)

    def test_live_default_uses_model_and_memory_and_retains_explicit_choice(self):
        shared = read("Shared/SharedSettings.swift")
        view = read("Sayboard/Views/SettingsNavigationViews.swift")
        self.assertIn("ProcessInfo.processInfo.physicalMemory >= 8 * 1_073_741_824", shared)
        self.assertIn("defaults.object(forKey: SharedKey.experimentalLiveDictationEnabled)", shared)
        self.assertIn("less than 8 GB of RAM", view)
        self.assertIn("1.5-second updates are a target", view)

    def test_history_only_deletes_voice_notes(self):
        history = read("Sayboard/Views/HistoryStorageSettingsView.swift")
        categories = read("Sayboard/Views/DataAndStorageSettingsView.swift")
        self.assertIn("Delete Voice Notes", history)
        self.assertIn("Meetings, learned suggestions and downloaded models are not affected",
                      history)
        self.assertIn("MeetingRecordsView()", categories)
        self.assertIn("LearningDataSettingsView()", categories)

    def test_user_initiated_export_includes_explicit_corrections(self):
        export = read("Shared/PersonalVocabularyExport.swift")
        settings = read("Sayboard/Views/LearningDataSettingsView.swift")
        self.assertIn("schemaVersion: 3", export)
        self.assertIn("manualSpeechCorrections", export)
        self.assertIn("cantoneseCorrectionRules.map", settings)
        self.assertIn("LatinSpeechCorrectionLearning.read", settings)
        self.assertIn("ConfirmedChoiceLearning.chineseCounts", settings)
        self.assertIn("self.showExporter = true", settings)

    def test_universal_cantonese_diagnostics_preserved(self):
        diagnostics = read("Sayboard/Views/DiagnosticsView.swift")
        model = read("Shared/CantoneseSchemePreference.swift")
        self.assertIn("CantoneseRomanizationDiagnosticsView()", diagnostics)
        self.assertIn("recent_weighted_counts", model)
        self.assertIn("recording_or_transcript_included", model)

    def test_explicit_unknown_word_learning_remains(self):
        suggestions = read("SayboardKeyboard/LatinWordSuggestions.swift")
        keyboard = read("SayboardKeyboard/Views/Layouts/AlphabeticKeyboardLayout.swift")
        self.assertIn("func rememberCustom(_ word: String, preferred: [String]) -> Bool",
                      suggestions)
        self.assertIn("let learnable = self.learnableLatinWord", keyboard)
        self.assertIn("expandedLatinCandidateGrid", keyboard)


if __name__ == "__main__":
    unittest.main()
