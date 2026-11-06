"""Baseline keyboard and host data deletion contracts."""
import unittest
from pathlib import Path
from test_keyboard_initial_layout import git_blob

ROOT = Path(__file__).resolve().parent.parent
def source(p): return (ROOT / p).read_text(encoding="utf-8")

class KeyboardSafetyContracts(unittest.TestCase):
    def test_delete_all_is_bounded_and_progress_checked(self):
        self.assertEqual(git_blob("SayboardKeyboard/KeyboardViewController.swift"),
                         "ae3e1e67e43859f3d339c27b5941d7cbed4ad2a5")
    def test_history_writes_before_audio_removal(self):
        h = source("Shared/HistoryStore.swift")
        one = h.split("func deleteRecord(id:", 1)[1].split("func deleteAllRecords()", 1)[0]
        all_records = h.split("func deleteAllRecords()", 1)[1].split("func retainedRecords(", 1)[0]
        self.assertLess(one.index("self.writeRecords"), one.index("self.deleteAudioFile"))
        self.assertLess(all_records.index("self.writeRecords"), all_records.index("self.deleteAudioFile"))
        self.assertIn('!fileName.contains("/")', h)
        self.assertIn("private func writeRecords(_ records: [HistoryRecord]) -> Bool", h)
    def test_async_llm_result_requires_request_and_document(self):
        self.assertEqual(git_blob("Shared/LLMBridge.swift"),
                         "a02381bf16c69ef61a8f5b48c19a1bcccac6914f")
        self.assertEqual(git_blob("SayboardKeyboard/KeyboardViewController.swift"),
                         "ae3e1e67e43859f3d339c27b5941d7cbed4ad2a5")
    def test_version_90_emoji_page_is_separate_from_native_globe(self):
        self.assertEqual(git_blob("SayboardKeyboard/Views/NativeInputModeSwitchKey.swift"),
                         "5401597201bed836e6e13ae07bb172f3a28dfe99")
        self.assertEqual(git_blob("SayboardKeyboard/Views/Layouts/KeyboardChrome.swift"),
                         "ac447fbf96bc9da7d8bd45de26463b74262a8e62")
    def test_touch_state_does_not_outlive_keyboard(self):
        self.assertEqual(git_blob("SayboardKeyboard/Views/AlphabeticTouchRow.swift"),
                         "9f457bd593aab09299ca88fa84e1909a9a26afc9")
        self.assertEqual(git_blob("SayboardKeyboard/KeyboardState.swift"),
                         "92d98e38e7566501215e2cd42a27a8e06617dc6f")

if __name__ == "__main__":
    unittest.main()
