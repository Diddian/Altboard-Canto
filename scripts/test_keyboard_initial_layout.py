"""Regression guards for stable keyboard hosting across focus changes."""
from pathlib import Path
import unittest

ROOT = Path(__file__).resolve().parent.parent
LAYOUT = ROOT / "SayboardKeyboard" / "Views" / "Layouts" / "AlphabeticKeyboardLayout.swift"
HOST = ROOT / "SayboardKeyboard" / "KeyboardViewController.swift"
ROOT_VIEW = ROOT / "SayboardKeyboard" / "Views" / "KeyboardView.swift"


class KeyboardInitialLayoutTests(unittest.TestCase):
    def test_letter_rows_remain_visible_and_rehydrate_on_reactivation(self):
        source = LAYOUT.read_text(encoding="utf-8")
        self.assertNotIn(".id(self.keyboardState.keyboardAppearanceRevision)", source)
        row = (ROOT / "SayboardKeyboard/Views/AlphabeticTouchRow.swift").read_text()
        self.assertIn(".onChange(of: self.appearanceRevision)", row)
        self.assertIn("resetToken: self.appearanceRevision", row)
        self.assertNotIn(".opacity(self.isCursorTracking ? 0.07 : 1)", source)
        self.assertNotIn(".allowsHitTesting(!self.isCursorTracking)", source)
        self.assertIn("self.firstKeyRow", source)
        self.assertIn("self.secondKeyRow", source)
        self.assertIn("self.thirdKeyRow", source)
        self.assertIn("@StateObject private var swipeTrail = SwipeTrailState()", source)
        self.assertIn("@ObservedObject var trail: SwipeTrailState", source)
        self.assertIn("onSwipePath: { path in self.swipeTrail.update(path) }", source)
        self.assertNotIn("@State private var liveSwipePath", source)

    def test_host_settings_before_swiftui_mount_and_heights_stay_in_sync(self):
        source = HOST.read_text(encoding="utf-8")
        appear = source.split("override func viewWillAppear(", 1)[1].split(
            "override func viewWillDisappear(", 1
        )[0]
        self.assertNotIn("self.setupKeyboardView()", appear)
        self.assertIn("self.keyboardState.refresh()", appear)
        self.assertIn("self.syncFullAccessIfChanged()", appear)
        self.assertNotIn("controller.rootView =", source)
        self.assertNotIn("rootNeedsMeasuredRemount", source)
        self.assertNotIn("constraintsAffectingLayout", source)
        self.assertNotIn("self.view.superview?.layoutIfNeeded()", source)
        self.assertIn("hosting.view.topAnchor.constraint(equalTo: self.view.topAnchor)", source)
        self.assertIn("hosting.sizingOptions = []", source)
        host = (ROOT / "SayboardKeyboard/KeyboardInputView.swift").read_text()
        self.assertIn("override func systemLayoutSizeFitting", host)
        self.assertIn(".frame(width: self.geometry.size.width, height: self.geometry.size.height", host)
        self.assertIn("kind: self.keyboardState.effectiveTypingKind", source)
        self.assertIn("self.hostingHeightConstraint, height.constant != target", source)
        self.assertIn("override func viewDidLayoutSubviews()", source)

    def test_one_effective_keyboard_route_and_one_expanded_lookup(self):
        root = ROOT_VIEW.read_text(encoding="utf-8")
        self.assertEqual(root.count("AlphabeticKeyboardLayout(proxy:"), 1)
        self.assertIn("switch self.keyboardState.effectiveTypingKind", root)
        self.assertNotIn("switch self.keyboardState.keyboardKind", root)
        self.assertNotIn(".id(self.keyboardState.keyboardAppearanceRevision)", root)
        self.assertIn(".transaction { $0.animation = nil }", root)
        layout = LAYOUT.read_text(encoding="utf-8")
        update = layout.split("private func updateCandidates()", 1)[1].split(
            "private func beginCursorTracking()", 1
        )[0]
        self.assertIn("let ranked = JyutpingDictionary.shared.candidates(", update)
        self.assertIn("for: prefix, limit: gridVisible ? 200 : 12", update)
        self.assertNotIn("for: prefix, limit: 200", update)

    def test_keyboard_lifecycle_trace_is_private_and_bounded(self):
        trace = (ROOT / "Shared/KeyboardLifecycleTrace.swift").read_text()
        controller = HOST.read_text()
        diagnostics = (ROOT / "Sayboard/Views/DiagnosticsView.swift").read_text()
        self.assertIn("#if !APPSTORE", trace)
        self.assertIn("private static let maxBytes: off_t = 1_048_576", trace)
        self.assertIn("flock(fd, LOCK_EX)", trace)
        self.assertIn('hostHint: safeHostHint(hostBundleHint)', trace)
        for private_content in ("documentContextBeforeInput", "selectedText", "insertText",
                                "audioBuffer", "touchPath"):
            self.assertNotIn(private_content, trace)
        for event in ("inputViewLoaded", "hostingMounted", "willAppear", "didAppear",
                      "willDisappear", "didDisappear", "layoutChanged", "documentChanged",
                      "switchRequirementChanged", "memoryWarning"):
            self.assertIn("self.recordKeyboardTrace(." + event + ")", controller)
        for label in ("Share Development Diagnostics JSON", "Copy Development Diagnostics JSON",
                      "Clear Development Traces"):
            self.assertIn(label, diagnostics)

    def test_feature_diagnostics_contract(self):
        trace = (ROOT / "Shared/FeatureDiagnostics.swift").read_text()
        screen = (ROOT / "Sayboard/Views/DiagnosticsView.swift").read_text()
        self.assertIn("#if !APPSTORE", trace)
        self.assertIn("private static let maxBytes: off_t = 1_048_576", trace)
        self.assertIn("flock(fd, LOCK_EX)", trace)
        self.assertIn("KeyboardLifecycleTrace.exportJSON()", trace)
        self.assertIn("KeyboardLifecycleTrace.clear()", trace)
        self.assertIn("KeyboardExperimentMetrics.read()", trace)
        self.assertIn("KeyboardHapticTrace.events", trace)
        self.assertIn('DisclosureGroup("Development Traces"', screen)
        for sensitive in ("documentContextBeforeInput", "selectedText", "audioSamples",
                          "request.text", "request.prompt", "hostBundleId", "touchPath"):
            self.assertNotIn(sensitive, trace)
        modules = {
            "Sayboard/Services/SpeechRecognitionService.swift": ".speech",
            "Sayboard/Services/SpeechRecognitionService+Transcription.swift": ".speech",
            "Sayboard/Services/SpeechRecognitionService+ExperimentalLive.swift": ".liveDictation",
            "Sayboard/Services/ModelDownloadService.swift": ".speechModel",
            "Sayboard/Services/ModelDownloadService+Execution.swift": ".speechModel",
            "Sayboard/Services/LLMDownloadService.swift": ".textModel",
            "Sayboard/Services/LLMProcessingCoordinator.swift": ".aiActions",
            "Sayboard/Services/MeetingRecordingCoordinator.swift": ".meeting",
            "Sayboard/Services/LocalUserDataStore.swift": ".data",
            "SayboardKeyboard/Views/Layouts/AlphabeticKeyboardLayout.swift": ".swipe",
            "Sayboard/Views/SpeechLanguagesSettingsView.swift": ".language",
        }
        for file, area in modules.items():
            with self.subTest(path=file):
                self.assertIn("FeatureDiagnostics.record(" + area, (ROOT / file).read_text())


if __name__ == "__main__":
    unittest.main()


