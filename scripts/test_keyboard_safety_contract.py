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

    def test_native_globe_replaces_retired_custom_emoji_route(self):
        layout = source("SayboardKeyboard/Views/Layouts/AlphabeticKeyboardLayout.swift")
        chrome = source("SayboardKeyboard/Views/Layouts/KeyboardChrome.swift")
        self.assertNotIn("showsEmojiPage", layout)
        self.assertNotIn("onEmojiAction", layout + chrome)
        self.assertIn("NativeInputModeSwitchKey(", chrome)

    def test_touch_state_does_not_outlive_keyboard(self):
        controller = source("SayboardKeyboard/KeyboardViewController.swift")
        delete = source("SayboardKeyboard/Views/RepeatDeleteButton.swift")
        self.assertIn("lastTouchDocumentID", controller)
        self.assertIn("KeyboardTouchLearning.shared.invalidate()", controller)
        self.assertIn("self.pressed = false", delete)
        self.assertIn("KeyboardTouchLearning.shared.invalidate()", delete)


if __name__ == "__main__":
    unittest.main()
