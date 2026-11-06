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
        self.assertIn(".id(self.keyboardState.keyboardAppearanceRevision)", source)
        self.assertIn("Keep composition, candidates and the bottom row mounted.", source)
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
        self.assertIn("GeometryReader { bounds in", host)
        self.assertIn(".frame(width: max(1, width), height: max(1, height)", host)
        self.assertNotIn("Color.clear", host)
        self.assertIn("kind: self.keyboardState.effectiveTypingKind", source)
        self.assertIn("self.hostingHeightConstraint, height.constant != target", source)
        self.assertIn("override func viewDidLayoutSubviews()", source)

    def test_render_probe_distinguishes_blank_root_from_key_rows(self):
        root = (ROOT / "SayboardKeyboard/KeyboardInputView.swift").read_text()
        view = ROOT_VIEW.read_text()
        layout = LAYOUT.read_text()
        row = (ROOT / "SayboardKeyboard/Views/AlphabeticTouchRow.swift").read_text()
        diagnostic = (ROOT / "Shared/FeatureDiagnostics.swift").read_text()
        self.assertIn("measured.width > 1 && measured.height > 1 ? .rootReady : .rootWaiting", root)
        self.assertIn("FeatureDiagnostics.record(.keyboardRender, .rootReady)", root)
        self.assertIn("GeometryReader { bounds in", root)
        self.assertIn("FeatureDiagnostics.record(.keyboardRender, .layoutMounted)", layout)
        self.assertIn("self.syncExpectedLetterRows()", layout)
        self.assertIn("self.keyboardState.expectsAlphabeticTouchRows = false", layout)
        self.assertIn("FeatureDiagnostics.record(.keyboardRender, .letterRowMounted)", row)
        self.assertIn("FeatureDiagnostics.record(.keyboardRender, .strokeGridMounted)", layout)
        self.assertIn("FeatureDiagnostics.record(.keyboardRender, .trailOverlayMounted)", layout)
        self.assertIn("FeatureDiagnostics.record(.keyboardRender, .llmPromptMounted)", view)
        self.assertIn("#if !APPSTORE", diagnostic)
        self.assertNotIn("touchPath", diagnostic)

    def test_delayed_render_probe_inspects_uikit_touch_targets_privately(self):
        host = HOST.read_text()
        lifecycle = (ROOT / "Shared/KeyboardLifecycleTrace.swift").read_text()
        self.assertIn("case renderCheckpoint", lifecycle)
        self.assertIn("case renderSuspicious", lifecycle)
        self.assertIn("case renderRefreshRequested", lifecycle)
        self.assertIn("let letterRowsExpected: Bool", lifecycle)
        self.assertIn("touchInWindow < 3", host)
        self.assertIn("afterMissingRowsRefresh", host)
        self.assertIn("self.missingRowsRefreshAttempted = true", host)
        self.assertIn("let renderProbe: RenderProbe?", lifecycle)
        self.assertIn('"renderReview": renderReview(for: events)', lifecycle)
        self.assertIn('let checkpoint: String', lifecycle)
        self.assertIn("ImmediateKeyTouchView", host)
        self.assertIn("input.hitTest(point, with: nil)", host)
        self.assertIn("scanned < 256", host)
        self.assertIn("DispatchQueue.main.asyncAfter(deadline: .now() + 0.35)", host)
        self.assertIn("guard let input = self.viewIfLoaded else { return }", host)
        self.assertNotIn("let input = self.view\\n", host)
        self.assertIn("self.scheduleRenderCheckpoint(checkpoint: \"afterAppear\")", host)
        self.assertIn("self.scheduleRenderCheckpoint(checkpoint: \"afterDocumentChange\")", host)
        self.assertIn("self.scheduleRenderCheckpoint(checkpoint: \"afterHostTextCleared\")", host)
        self.assertIn("case hostTextCleared", lifecycle)
        self.assertIn("postSubmitReview(for: events)", lifecycle)
        self.assertIn("\"sessionsWithUnmatchedWillDisappear\": missingCompletion.count", lifecycle)
        self.assertIn('self.recordKeyboardTrace(.hostTextCleared)', host)
        self.assertIn("previousHostHasText == true && !currentHostHasText", host)
        self.assertIn("self.lastObservedHostHasText = currentHostHasText", host)
        self.assertIn("self.renderProbeGeneration &+= 1", host)
        for private_content in ("documentContextBeforeInput", "selectedText", "insertText",
                                "audioBuffer", "touchPath", "pointX", "pointY"):
            self.assertNotIn(private_content, lifecycle)

    def test_drawing_view_exists_only_for_an_active_trail(self):
        source = LAYOUT.read_text()
        overlay = source.split("private struct SwipeTrailOverlay: View", 1)[1].split(
            "private struct ActiveSwipeTrail:", 1)[0]
        self.assertIn("if self.trail.points.count > 1", overlay)
        self.assertIn("ActiveSwipeTrail(points: self.trail.points)", overlay)
        self.assertIn("view.isUserInteractionEnabled = false", source)
        self.assertIn(".allowsHitTesting(false)", source)
        touch = (ROOT / "SayboardKeyboard/Views/AlphabeticTouchRow.swift").read_text()
        finish = touch.split("private func finishTouch(", 1)[1]
        self.assertIn("self.onSwipePath([])", finish)

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

    def test_memory_diagnostics_sample_only_on_lifecycle_or_idle_timer(self):
        sampler = (ROOT / "Shared/KeyboardProcessMemory.swift").read_text()
        trace = (ROOT / "Shared/KeyboardLifecycleTrace.swift").read_text()
        host = HOST.read_text()
        self.assertIn("os_proc_available_memory()", sampler)
        self.assertIn("task_info(mach_task_self_", sampler)
        self.assertIn("info.phys_footprint", sampler)
        self.assertIn("processLaunchID", sampler)
        self.assertIn("let processMemory: KeyboardProcessMemory.Snapshot?", trace)
        self.assertIn("event.samplesProcessMemory", trace)
        self.assertIn("case memorySample", trace)
        self.assertIn("case .inputViewLoaded, .hostingMounted", trace)
        self.assertIn('"memoryReview": memoryReview(for: events)', trace)
        self.assertIn('"recentProcessLaunches": summaries', trace)
        self.assertIn('"minimumHeadroomMiB": available.min()', trace)
        self.assertIn("timeInterval: 8", host)
        self.assertIn("self.startMemoryWatch()", host)
        self.assertIn("self.stopMemoryWatch()", host)
        self.assertIn("guard self.viewIfLoaded?.window != nil else { return }", host)
        self.assertNotIn("keyboardState.textContextRevision", sampler)
        for forbidden in ("documentContextBeforeInput", "hostBundleId", "touchPath",
                          "insertText(", "transcript", "audioBuffer"):
            self.assertNotIn(forbidden, sampler)

    def test_feature_diagnostics_contract(self):
        trace = (ROOT / "Shared/FeatureDiagnostics.swift").read_text()
        screen = (ROOT / "Sayboard/Views/DiagnosticsView.swift").read_text()
        self.assertIn("#if !APPSTORE", trace)
        self.assertIn("private static let maxBytes: off_t = 1_048_576", trace)
        self.assertIn("flock(fd, LOCK_EX)", trace)
        self.assertIn("KeyboardLifecycleTrace.exportJSON()", trace)
        self.assertIn("KeyboardLifecycleTrace.clear()", trace)
        self.assertIn("KeyboardExperimentMetrics.read()", trace)
        self.assertIn('"patternsForReview": patterns(in: featureEvents)', trace)
        self.assertIn('event == "started" || event == "queued"', trace)
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
            "Shared/TranscriptionBridge.swift": ".bridge",
            "Shared/LLMBridge.swift": ".bridge",
            "SayboardKeyboard/KeyboardViewController.swift": ".bridge",
            "SayboardKeyboard/KeyboardViewController+LLM.swift": ".bridge",
        }
        for file, area in modules.items():
            with self.subTest(path=file):
                self.assertIn("FeatureDiagnostics.record(" + area, (ROOT / file).read_text())


if __name__ == "__main__":
    unittest.main()


