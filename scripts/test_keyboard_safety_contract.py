"""Regression contracts for keyboard document identity and safe cleanup."""

from pathlib import Path
import unittest

ROOT = Path(__file__).resolve().parent.parent


def source(path: str) -> str:
    return (ROOT / path).read_text(encoding="utf-8")


class KeyboardSafetyContracts(unittest.TestCase):
    def test_delete_all_is_bounded_and_progress_checked(self):
        controller = source("SayboardKeyboard/KeyboardViewController.swift")
        action = controller.split("private func deleteAllText()", 1)[1].split(
            "private func startDictationViaDarwin()", 1
        )[0]
        self.assertIn("for _ in 0..<4_096", action)
        self.assertIn("documentContextBeforeInput", action)
        self.assertNotIn("while textDocumentProxy.hasText", action)

    def test_history_writes_before_audio_removal(self):
        history = source("Shared/HistoryStore.swift")
        delete_one = history.split("func deleteRecord(id:", 1)[1].split(
            "func deleteAllRecords()", 1
        )[0]
        delete_all = history.split("func deleteAllRecords()", 1)[1].split(
            "func retainedRecords(", 1
        )[0]
        self.assertLess(delete_one.index("self.writeRecords"), delete_one.index("self.deleteAudioFile"))
        self.assertLess(delete_all.index("self.writeRecords"), delete_all.index("self.deleteAudioFile"))
        self.assertIn('!fileName.contains("/")', history)
        self.assertIn("private func writeRecords(_ records: [HistoryRecord]) -> Bool", history)

    def test_async_llm_result_requires_request_and_document(self):
        bridge = source("Shared/LLMBridge.swift")
        actions = source("SayboardKeyboard/KeyboardViewController+LLM.swift")
        self.assertIn("let requestID: UUID", bridge)
        self.assertIn("readResult(matching requestID: UUID?)", bridge)
        self.assertIn("self.llmRequestID = request.requestID", actions)
        self.assertIn("currentLLMFieldMatches()", actions)
        self.assertIn("self.keyboardState.llmError = .storageUnavailable", actions)

    def test_version_90_emoji_page_is_separate_from_native_globe(self):
        layout = source("SayboardKeyboard/Views/Layouts/AlphabeticKeyboardLayout.swift")
        chrome = source("SayboardKeyboard/Views/Layouts/KeyboardChrome.swift")
        glyph = source("Shared/NativeEmojiGlyph.swift")
        self.assertIn("EmojiKeyboardView(", layout)
        self.assertIn("onEmojiAction: { self.openEmojiPage() }", layout)
        self.assertIn("self.showsEmojiPage = true", layout)
        self.assertIn("self.showsEmojiPage = false", layout)
        self.assertIn("case .nativeEmojiGlyph:", source("SayboardKeyboard/Views/KeyButton.swift"))
        self.assertIn("struct NativeEmojiGlyph: Shape", glyph)
        self.assertIn("KeyButton(content: .nativeEmojiGlyph", chrome)
        self.assertIn("NativeInputModeSwitchKey(", chrome)
        self.assertIn('iconName: "globe"', chrome)
        self.assertIn("if let openEmoji = self.onEmojiAction", chrome)
        self.assertIn(", keyboardEmoji", source("Shared/FeatureDiagnostics.swift"))

    def test_voice_output_selection_is_checked_before_delivery(self):
        service = source("Sayboard/Services/SpeechRecognitionService.swift")
        pipeline = source("Sayboard/Services/SpeechRecognitionService+Transcription.swift")
        button = source("SayboardKeyboard/Views/TranslateToggleButton.swift")
        self.assertNotIn("recordingOutputOptions", service)
        self.assertNotIn("recordingOutputOptions", pipeline)
        self.assertIn("let options = self.settings.voiceOutputConfiguration", pipeline)
        self.assertGreaterEqual(pipeline.count("VoiceOutputSelectionPolicy.decide("), 2)
        self.assertIn("self.settings.synchronize()", pipeline)
        last_selection = pipeline.rindex("VoiceOutputSelectionPolicy.decide(")
        punctuation = pipeline.index("VoicePunctuationPolicy.render(")
        delivery = pipeline.index("TranscriptionBridge.writeTranscription(finalOutput)")
        self.assertLess(last_selection, punctuation)
        self.assertLess(punctuation, delivery)
        self.assertIn("enabled: options.punctuationEnabled", pipeline)
        self.assertIn("self.targetRawValue = next.target.rawValue", button)
        self.assertIn("FeatureDiagnostics.record(.voiceOutput, .selected)", button)

    def test_touch_state_does_not_outlive_keyboard(self):
        controller = source("SayboardKeyboard/KeyboardViewController.swift")
        delete = source("SayboardKeyboard/Views/RepeatDeleteButton.swift")
        self.assertIn("lastTouchDocumentID", controller)
        self.assertIn("KeyboardTouchLearning.shared.invalidate()", controller)
        self.assertIn("self.pressed = false", delete)
        self.assertIn("KeyboardTouchLearning.shared.invalidate()", delete)


if __name__ == "__main__":
    unittest.main()
