#!/usr/bin/env python3
"""Static QA for settings contracts; does not modify user defaults."""
import pathlib
import unittest

ROOT = pathlib.Path(__file__).resolve().parent.parent

class SettingsContractTests(unittest.TestCase):
    def test_default_swipe_and_uncluttered_keyboard_settings(self):
        keyboard = (ROOT / "Sayboard" / "Views" / "KeyboardSettingsView.swift").read_text()
        layout = (ROOT / "SayboardKeyboard" / "Views" / "Layouts"
                  / "AlphabeticKeyboardLayout.swift").read_text()
        self.assertNotIn('Picker("Cantonese Romanization"', keyboard)
        self.assertNotIn('Toggle("Swipe Typing (English / German)"', keyboard)
        self.assertIn('private let swipeTypingEnabled = true', layout)
        self.assertIn('Label("Haptic Feedback"', keyboard)
        self.assertNotIn('Slider(value: self.$hapticStrength', keyboard)
        self.assertNotIn('Picker("Haptic Method"', keyboard)
        self.assertNotIn('NavigationLink("All Keyboard Diagnostics")', keyboard)
        self.assertIn('Label("Show Settings Key"', keyboard)
        self.assertIn('Label("Double-Space Period"', keyboard)
        self.assertIn('Label("Auto-capitalize Sentences"', keyboard)
        self.assertLess(keyboard.index('KeyboardTestPreview('),
                        keyboard.index('private struct KeyboardTestPreview'))

    def test_settings_controls_have_icon_labels(self):
        files = (
            "Sayboard/Views/SettingsView.swift",
            "Sayboard/Views/SettingsNavigationViews.swift",
            "Sayboard/Views/SpeechLanguagesSettingsView.swift",
            "Sayboard/Views/KeyboardSettingsView.swift",
            "Sayboard/Views/TextOutputSection.swift",
        )
        for path in files:
            with self.subTest(path=path):
                content = (ROOT / path).read_text()
                self.assertIn('Label(', content)
        keyboard = (ROOT / "Sayboard/Views/KeyboardSettingsView.swift").read_text()
        for name in ("Keyboard Type", "Key Order", "Auto-capitalize Sentences",
                     "Double-Space Period", "Haptic Feedback", "Show Settings Key"):
            self.assertIn('Label("' + name + '"', keyboard)

    def test_meeting_titles_notes_preserve_existing_records(self):
        coordinator = (ROOT / "Sayboard/Services/MeetingRecordingCoordinator.swift").read_text()
        meeting_view = (ROOT / "Sayboard/Views/MeetingRecordsView.swift").read_text()
        self.assertIn("var title: String?", coordinator)
        self.assertIn("var notes: String?", coordinator)
        self.assertIn("func updateRecord(id: UUID, title: String, notes: String)", coordinator)
        self.assertIn("private func writeManifest(_ record: MeetingRecord)", coordinator)
        self.assertIn("Meeting name (optional)", meeting_view)
        self.assertIn("Meeting notes (optional)", meeting_view)
        self.assertIn("record.displayTitle", meeting_view)
        self.assertIn("Save Meeting Details", meeting_view)

    def test_cantonese_learning_export_is_private(self):
        diagnostics = (ROOT / "Sayboard/Views/DiagnosticsView.swift").read_text()
        view = (ROOT / "Sayboard/Views/CantoneseRomanizationDiagnosticsView.swift").read_text()
        model = (ROOT / "Shared/CantoneseSchemePreference.swift").read_text()
        dictionary = (ROOT / "SayboardKeyboard/JyutpingDictionary.swift").read_text()
        self.assertIn("CantoneseRomanizationDiagnosticsView()", diagnostics)
        self.assertIn("Share Diagnostic JSON", view)
        self.assertIn("Copy Diagnostic JSON", view)
        self.assertIn("UIActivityViewController", view)
        self.assertIn("CantoneseSchemePreference.diagnosticJSON(", view)
        self.assertIn("AppGroup.sharedDefaults", view)
        self.assertIn("candidate_words_included", model)
        self.assertIn("recent_weighted_counts", model)
        self.assertIn("recording_or_transcript_included", model)
        self.assertIn("candidateCounts.count", model)
        self.assertNotIn("candidateCounts.keys", model)
        self.assertNotIn("candidateCounts.map", model)
        self.assertIn("CantoneseSchemePreference.preferenceStorageKey", dictionary)
        self.assertIn("CantoneseSchemePreference.candidateStorageKey", dictionary)

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
        self.assertIn('Label("Double-Space Period"', keyboard)
        self.assertIn('CantoneseCorrectionsView()', keyboard)
        self.assertIn('preferredSpokenLanguages.contains("yue")', keyboard)
        self.assertNotIn('CantoneseCorrectionsView()', voice)
        self.assertIn('onPreferredLanguagesChanged', speech)
        self.assertIn('cantoneseSelected: self.preferredSpokenLanguages.contains("yue")', home)

    def test_speech_dictation_order_and_one_line_note(self):
        home = (ROOT / "Sayboard" / "Views" / "SettingsView.swift").read_text()
        self.assertIn('Text("Speech & Dictation")', home)
        self.assertIn('Text("When active,")', home)
        self.assertIn('Image(systemName: "mic.fill")', home)
        self.assertIn('.fixedSize(horizontal: true, vertical: false)', home)
        self.assertLess(home.index('rowsOnly: true'), home.index('rows: .session'))
        self.assertLess(home.index('rows: .session'), home.index('VoiceOutputSettingsView()'))
        self.assertLess(home.index('VoiceOutputSettingsView()'), home.index('rows: .meeting'))
        self.assertLess(home.index('rows: .meeting'), home.index('ModelsView()'))
        self.assertLess(home.index('ModelsView()'), home.index('TextAISettingsView()'))
        self.assertNotIn('TextOutputSection(showFooter: false)', home)

    def test_explicit_unknown_word_learning_is_bounded(self):
        suggestions = (ROOT / "SayboardKeyboard/LatinWordSuggestions.swift").read_text()
        layout = (ROOT / "SayboardKeyboard/Views/Layouts/AlphabeticKeyboardLayout.swift").read_text()
        self.assertIn('func rememberCustom(_ word: String, preferred: [String]) -> Bool', suggestions)
        self.assertIn('self.remember(LatinWordSuggestion(text: cleaned, language: language))', suggestions)
        self.assertIn('first.isLetter, last.isLetter', suggestions)
        self.assertIn('"aite"', suggestions)
        self.assertIn('let learnable = self.learnableLatinWord', layout)
        self.assertIn('expandedLatinCandidateGrid', layout)
        self.assertIn('Dismiss candidate suggestions', layout)
        self.assertIn('Text(verbatim: self.shapeDisplay)', layout)

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
