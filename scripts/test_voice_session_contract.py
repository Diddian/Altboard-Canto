"""Cross-process wiring and privacy contracts for the voice readiness lease."""
import json
from pathlib import Path
import unittest

ROOT = Path(__file__).resolve().parent.parent


class VoiceSessionContractTests(unittest.TestCase):
    def test_keyboard_activity_never_activates_audio(self):
        source = (ROOT / "SayboardKeyboard/KeyboardViewController+VoiceSession.swift").read_text()
        self.assertIn("guard self.hasFullAccess", source)
        self.assertIn("keyboardVoiceActivityChanged", source)
        self.assertIn("forMode: .common", source)
        for forbidden in ("startSession(", "startCapture(", "requestStartDictation", "hostBundleId", "documentContext"):
            self.assertNotIn(forbidden, source)

    def test_lifecycle_renews_and_ends_bounded_visibility(self):
        controller = (ROOT / "SayboardKeyboard/KeyboardViewController.swift").read_text()
        for callback, action in (("override func viewDidAppear", "startVoiceSessionActivity()"),
                                 ("override func viewWillDisappear", "stopVoiceSessionActivity()")):
            body = controller.split(callback, 1)[1].split("\n  }", 1)[0]
            self.assertIn(action, body)
        app = (ROOT / "Sayboard/SayboardApp.swift").read_text()
        self.assertIn("self.speechService.session.setHostForeground(phase != .background)", app)

    def test_host_owns_timeout_and_observes_visibility(self):
        audio = (ROOT / "Sayboard/Services/BackgroundAudioSession.swift").read_text()
        service = (ROOT / "Sayboard/Services/SpeechRecognitionService.swift").read_text()
        self.assertIn("self.idleCountdown.evaluate(", audio)
        self.assertIn("capturing: self.captureOwner != nil", audio)
        self.assertIn("keyboard: self.settings.voiceKeyboardActivity", audio)
        self.assertIn("DarwinNotificationName.keyboardVoiceActivityChanged", service)
        self.assertIn("self?.session.keyboardActivityDidChange()", service)

    def test_readiness_is_backed_by_real_input(self):
        audio = (ROOT / "Sayboard/Services/BackgroundAudioSession.swift").read_text()
        start = audio.split("func startSession()", 1)[1].split("func endSession()", 1)[0]
        self.assertNotIn("self.settings.mainAppHeartbeat = CFAbsoluteTimeGetCurrent()", start)
        self.assertIn("self.settings.mainAppHeartbeat = 0", start)
        tap = audio.split("private func installPersistentTap()", 1)[1].split("private func resetInactivityTimer()", 1)[0]
        self.assertIn("AppGroup.sharedDefaults?.set(now, forKey: SharedKey.mainAppHeartbeat)", tap)
        self.assertIn("guard let active else { return }", tap)
        self.assertLess(tap.index("guard let active else { return }"), tap.index("active.recorder.appendBuffer"))
        state = (ROOT / "SayboardKeyboard/KeyboardState.swift").read_text()
        self.assertIn("VoiceSessionPolicy.isReady(", state)

    def test_activity_has_no_content_or_host_identifiers(self):
        policy = (ROOT / "Shared/VoiceSessionPolicy.swift").read_text()
        activity = policy.split("struct KeyboardActivity", 1)[1].split("func isActive", 1)[0]
        self.assertEqual(activity.count("let "), 3)
        for name in ("owner: UUID", "updatedAt: TimeInterval", "visible: Bool"):
            self.assertIn(name, activity)
        settings = (ROOT / "Shared/SharedSettings.swift").read_text()
        self.assertIn("newValue.visible ? SharedKey.voiceKeyboardActivity : SharedKey.voiceKeyboardActivityEnded", settings)

    def test_diagnostics_cover_idle_start_cancel_expiry(self):
        audio = (ROOT / "Sayboard/Services/BackgroundAudioSession.swift").read_text()
        for event in (".voiceSession, .started", ".voiceSession, .stopped", ".voiceSession, .failed",
                      ".voiceSession, .timedOut", ".idleStarted : .idleCancelled", ".voiceSession, .interrupted"):
            self.assertIn(event, audio)
        state = (ROOT / "SayboardKeyboard/KeyboardState.swift").read_text()
        self.assertIn("if ready && !self.isSessionActive", state)
        self.assertIn("FeatureDiagnostics.record(.voiceSession, .ready)", state)

    def test_session_copy_has_translations_without_battery_guesses(self):
        catalog = json.loads((ROOT / "Shared/VoiceSession.xcstrings").read_text())
        for key, entry in catalog["strings"].items():
            for language in ("zh-Hant", "zh-Hans", "de"):
                self.assertTrue(entry["localizations"][language]["stringUnit"]["value"], (key, language))
        source = (ROOT / "Sayboard/Views/SessionInfoView.swift").read_text()
        self.assertNotIn("15%", source)
        self.assertNotIn("microphone only turns on", source)


if __name__ == "__main__":
    unittest.main()
