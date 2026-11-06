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
        for heading in ('Section("Speech & AI")', 'Text("App")'):
            self.assertIn(heading, home)
        for path in ("SpeechLanguagesSettingsView(", "DictationSettingsView(inline: true)",
                     "LLMSettingsView(inline: true)",
                     "KeyboardSettingsView(", "DataAndStorageSettingsView(inline: true)", "LLMModelsScreen()",
                     "AppLanguageListView()", "DiagnosticsView()"):
            self.assertIn(path, home)
        self.assertNotIn("DictationSettingsView()", home)
        self.assertIn("Altboard-Canto · Source on GitHub", home)
        self.assertNotIn('Section("Start Here")', home)
        self.assertNotIn('Is My Microphone Ready?', home)
        self.assertIn('ActiveSessionToggle()', home)
        layout = read("Sayboard/Views/KeyboardSettingsView.swift")
        self.assertIn('KeyboardCustomizationView(inline: true)', layout)
        self.assertNotIn('KeyboardCustomizationView(', home)
        self.assertIn('Label("History & Storage", systemImage: "externaldrive")', home)
        self.assertNotIn('VoiceOutputSettingsView()', home)
        self.assertEqual(home.count("ActiveSessionToggle()"), 1)
        self.assertNotIn("ActiveSessionToggle()", read("Sayboard/Views/SettingsNavigationViews.swift"))
        self.assertIn('selectedKind: self.keyboardKindBinding, inline: true', home)

    def test_inline_actions_and_test_field_clear(self):
        home = read("Sayboard/Views/SettingsView.swift")
        history = read("Sayboard/Views/HistoryListView.swift")
        ai = read("Sayboard/Views/LLMSettingsView.swift")
        self.assertEqual(home.count("DisclosureGroup(isExpanded: self.$showsDictation)"), 1)
        self.assertEqual(home.count("DisclosureGroup(isExpanded: self.$showsAIActions)"), 1)
        self.assertEqual(home.count("DictationSettingsView(inline: true)"), 1)
        self.assertEqual(home.count("LLMSettingsView(inline: true)"), 1)
        self.assertIn('Toggle("Enabled", isOn: self.$llmEnabled)', ai)
        self.assertIn('if self.keyboardTestingText.isEmpty {', history)
        self.assertIn('self.isKeyboardTestFocused = false\n        } else {\n          self.keyboardTestingText = ""', history)
        self.assertIn('"Close test keyboard" : "Clear test text"', history)
        self.assertIn("Settings → Speech & AI → Speech Model",
                      read("Sayboard/Views/MeetingRecordsView.swift"))

    def test_sections_with_footers_use_explicit_headers(self):
        sections = {
            "Sayboard/Views/SettingsView.swift": ("App",),
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
        self.assertNotIn('Text("Preview")', layout)
        self.assertEqual(layout.count("    Section {"), 1)
        self.assertLess(layout.index('Label("Key Order"'), layout.index('Label("Customization"'))
        self.assertLess(layout.index('Label("Customization"'), layout.index("KeyboardTestPreview("))
        self.assertNotIn("Section(", custom)
        self.assertNotIn("Slider(", custom)
        self.assertNotIn('Text("Strength")', custom)
        for control in ('Auto-capitalization', 'Double-Space Period',
                        'Haptic Feedback', 'Extra Globe Key', 'Settings Key',
                        'Output Key', 'AI Key'):
            self.assertIn(control, custom)
        self.assertNotIn('Text("Not yet available")', custom)

    def test_settings_routes_have_single_owners(self):
        routes = read("Sayboard/Views/SettingsNavigationViews.swift")
        output = read("Sayboard/Views/VoiceOutputSettingsView.swift")
        ai = read("Sayboard/Views/LLMSettingsView.swift")
        models = read("Sayboard/Views/ModelsView.swift")
        languages = read("Sayboard/Views/SpeechLanguagesSettingsView.swift")
        self.assertNotIn("ModelsView()", routes + output + languages)
        self.assertNotIn("LLMModelsScreen()", output + languages)
        self.assertNotIn("self.modelsSection", ai)
        self.assertNotIn("LLMModelsSection()", models)
        self.assertNotIn("languagePrefVariant", models)
        self.assertIn("mode: .ordered(", languages)
        self.assertNotIn("updated.subtracting", languages)

    def test_native_emoji_switcher_and_opt_in_top_globe(self):
        keyboard = read("SayboardKeyboard/Views/Layouts/KeyboardChrome.swift")
        state = read("SayboardKeyboard/KeyboardState.swift")
        config = read("Shared/SharedSettings.swift")
        preview = read("Sayboard/Views/KeyboardSettingsView.swift")
        controller = read("SayboardKeyboard/KeyboardViewController.swift")
        custom = read("Sayboard/Views/KeyboardCustomizationView.swift")
        native = read("SayboardKeyboard/Views/NativeInputModeSwitchKey.swift")
        alphabet = read("SayboardKeyboard/Views/Layouts/AlphabeticKeyboardLayout.swift")
        self.assertNotIn("keyboardGlobeTemporarilyDisabled", config + keyboard + preview + controller + custom)
        self.assertIn("var keyboardShowGlobeKey: Bool", config)
        self.assertIn("self.showGlobeKey = self.settings.keyboardShowGlobeKey", state)
        self.assertIn('private var showGlobe = false', custom)
        self.assertIn('Toggle("Extra Globe Key", isOn: self.$showGlobe)', custom)
        self.assertIn("var showsGlobeButton: Bool", keyboard)
        self.assertIn("var needsInputModeSwitchKey: Bool", config)
        self.assertIn("if self.keyboardState.showsGlobeButton", keyboard)
        self.assertIn('iconName = "globe"', native)
        self.assertIn("self.emojiPreview(width: 48)", preview)
        self.assertIn('KeyButton(content: .nativeEmojiGlyph', keyboard)
        self.assertIn("EmojiKeyboardView(", alphabet)
        self.assertIn('onEmojiAction: { self.openEmojiPage() }', alphabet)
        self.assertIn('Label("Formatting", systemImage: "text.alignleft")',
                      read("Sayboard/Views/LLMSettingsView.swift"))
        storage = read("Sayboard/Views/DataAndStorageSettingsView.swift")
        self.assertGreaterEqual(storage.count(".frame(minHeight: 64)"), 3)
        self.assertIn('iconName: "globe"', alphabet)
        self.assertIn('if self.keyboardState.showGlobeKey', alphabet)
        self.assertLess(alphabet.index('if self.keyboardState.showGlobeKey'),
                        alphabet.index('if self.keyboardState.showSettingsKey'))
        self.assertEqual(preview.count("if self.showsGlobeButton"), 2)
        self.assertIn("NativeInputModeSwitchKey(", keyboard)
        self.assertIn("#selector(handleInputModeList(from:with:))", controller)

    def test_output_and_formatting_have_one_owner(self):
        dictation = read("Sayboard/Views/SettingsNavigationViews.swift")
        actions = read("Sayboard/Views/LLMSettingsView.swift")
        output = read("Sayboard/Views/VoiceOutputSettingsView.swift")
        formatting = read("Sayboard/Views/TextOutputSection.swift")
        self.assertIn("DisclosureGroup(isExpanded: self.$showsOutput)", dictation)
        self.assertIn("VoiceOutputSettingsView(inline: true)", dictation)
        self.assertNotIn("VoiceOutputSettingsView(", actions)
        self.assertIn("DisclosureGroup(isExpanded: self.$showsFormatting)", actions)
        self.assertEqual(actions.count("TextOutputSection(inline: true)"), 1)
        self.assertNotIn("TextOutputSection(", output)
        self.assertIn("var inline = false", formatting)
        self.assertIn("var inline = false", output)
        self.assertLess(actions.index("TextOutputSection(inline: true)"),
                        actions.index("if self.llmEnabled && self.llmDownloadService.hasUsableModel"))

    def test_no_custom_swipe_to_switch_app_tabs(self):
        tabs = read("Sayboard/Views/MainTabView.swift")
        self.assertNotIn("pageSwipe(for:", tabs)
        self.assertNotIn("AppPageSwipe.destination(", tabs)
        self.assertEqual(tabs.count("TabView(selection: self.$selectedTab)"), 2)

    def test_host_keeps_render_tree_across_focus_changes(self):
        controller = read("SayboardKeyboard/KeyboardViewController.swift")
        host = read("SayboardKeyboard/KeyboardInputView.swift")
        self.assertIn("KeyboardHostGeometry()", controller)
        self.assertIn("self.hostGeometry.update(", controller)
        self.assertNotIn("controller.rootView =", controller)
        self.assertNotIn("rootNeedsMeasuredRemount", controller)
        self.assertIn("self.geometry.size.width > 1", host)
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
        self.assertIn("SharedSettings().experimentalLiveDictationEnabled = enabled", view)
        self.assertIn("guard self.experimentalLiveEnabled != enabled", view)

    def test_history_only_deletes_voice_notes(self):
        history = read("Sayboard/Views/HistoryStorageSettingsView.swift")
        categories = read("Sayboard/Views/DataAndStorageSettingsView.swift")
        self.assertIn("Delete Voice Notes", history)
        self.assertIn("Meetings, learned suggestions and downloaded models are not affected",
                      history)
        self.assertNotIn("NavigationLink", categories)
        for label in ("Export All Data", "Delete All Data"):
            self.assertIn(label, categories)
        self.assertIn("recordingActive", categories)
        store = read("Sayboard/Services/LocalUserDataStore.swift")
        self.assertIn("recorder.deleteAllRecords()", store)
        self.assertIn("try fm.zipItem(at:", store)

    def test_user_initiated_export_includes_explicit_corrections(self):
        export = read("Shared/PersonalVocabularyExport.swift")
        settings = read("Sayboard/Views/LearningDataSettingsView.swift")
        self.assertIn("schemaVersion: 3", export)
        self.assertIn("manualSpeechCorrections", export)
        store = read("Sayboard/Services/LocalUserDataStore.swift")
        self.assertIn("cantoneseCorrectionRules.map", store)
        self.assertIn("LatinSpeechCorrectionLearning.read", store)
        self.assertIn("ConfirmedChoiceLearning.chineseCounts", store)
        self.assertIn("LocalUserDataStore.vocabularyData()", settings)
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



