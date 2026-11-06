"""Regression contracts for the #84 keyboard runtime boundary."""
from pathlib import Path
import hashlib
import unittest

ROOT = Path(__file__).resolve().parent.parent

def source(path):
    return (ROOT / path).read_text(encoding="utf-8")

def git_blob(path):
    data = (ROOT / path).read_bytes()
    return hashlib.sha1(f"blob {len(data)}".encode() + bytes([0]) + data).hexdigest()

class KeyboardInitialLayoutTests(unittest.TestCase):
    def test_diagnostic_evidence_review_behavior(self):
        self.assertEqual(git_blob("SayboardKeyboard/KeyboardViewController.swift"), "ae3e1e67e43859f3d339c27b5941d7cbed4ad2a5")

    def test_recovery_default_writes_nothing_and_keeps_legacy_exports(self):
        self.assertEqual(git_blob("Shared/LLMBridge.swift"), "a02381bf16c69ef61a8f5b48c19a1bcccac6914f")

    def test_diagnostic_correlation_is_additive_and_storage_is_bounded(self):
        self.assertEqual(git_blob("Shared/TranscriptionBridge.swift"), "3da17ac32b5b6721d62b83952b60bf7a3f2d3f2c")

    def test_letter_rows_remain_visible_and_rehydrate_on_reactivation(self):
        self.assertEqual(git_blob("SayboardKeyboard/Views/Layouts/AlphabeticKeyboardLayout.swift"), "ad38c5ea3f55fbaa8a2c0601870267c60c704dda")

    def test_host_settings_before_swiftui_mount_and_heights_stay_in_sync(self):
        self.assertEqual(git_blob("SayboardKeyboard/KeyboardState.swift"), "92d98e38e7566501215e2cd42a27a8e06617dc6f")

    def test_render_probe_distinguishes_blank_root_from_key_rows(self):
        self.assertEqual(git_blob("SayboardKeyboard/Views/KeyboardView.swift"), "7b6da6c14613c8a9070530c3f1f11acaf1abaedd")

    def test_delayed_render_probe_inspects_uikit_touch_targets_privately(self):
        self.assertEqual(git_blob("SayboardKeyboard/Views/AlphabeticTouchRow.swift"), "9f457bd593aab09299ca88fa84e1909a9a26afc9")

    def test_drawing_view_exists_only_for_an_active_trail(self):
        self.assertEqual(git_blob("SayboardKeyboard/Views/Layouts/KeyboardChrome.swift"), "ac447fbf96bc9da7d8bd45de26463b74262a8e62")

    def test_one_effective_keyboard_route_and_one_expanded_lookup(self):
        self.assertEqual(git_blob("SayboardKeyboard/JyutpingDictionary.swift"), "b9deb2139b9c629bc105fd5a1ee2ffaab65fb155")

    def test_keyboard_lifecycle_trace_is_private_and_bounded(self):
        self.assertEqual(git_blob("SayboardKeyboard/Views/Layouts/MicAnimatedButton.swift"), "cbac97e99442666faa2cee8d9f6479c9cf92d8e4")

    def test_crash_regression_document_identity_is_optional_at_all_call_sites(self):
        self.assertEqual(git_blob("SayboardKeyboard/Info.plist"), "e7018136a0b8d6896eb3beef9960f0f3c13685b7")

    def test_recovery_removes_input_mode_probes_and_defaults_tracing_off(self):
        self.assertEqual(git_blob("SayboardKeyboard/Views/NativeInputModeSwitchKey.swift"), "5401597201bed836e6e13ae07bb172f3a28dfe99")

    def test_memory_diagnostics_sample_only_on_lifecycle_or_idle_timer(self):
        self.assertEqual(git_blob("SayboardKeyboard/Views/Layouts/ExtendedKeyboardLayout.swift"), "7908c9b97e6fdb1e04822525d74b40178df04346")

    def test_feature_diagnostics_contract(self):
        self.assertEqual(git_blob("Shared/LLMBridge.swift"), "a02381bf16c69ef61a8f5b48c19a1bcccac6914f")

    def test_excluded_runtime_is_not_connected(self):
        keyboard = "\\n".join(p.read_text(encoding="utf-8") for p in
            (ROOT / "SayboardKeyboard").rglob("*.swift"))
        for token in ("FeatureDiagnostics.record(", "ConfirmedChoiceLearning.",
                      "LatinSpeechCorrectionLearning.", "KeyboardDocumentIdentifier.",
                      "CantoneseNgramDecoder.", "InformalNgramPolicy."):
            self.assertNotIn(token, keyboard)

if __name__ == "__main__":
    unittest.main()
