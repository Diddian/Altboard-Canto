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
        self.assertIn(".id(self.keyboardState.keyboardTouchRowsRecoveryRevision)", source)
        self.assertNotIn(".id(self.keyboardState.keyboardAppearanceRevision)", source)
        self.assertIn("Ordinary field switches reset touch state without replacing the rows.", source)
        state = (ROOT / "SayboardKeyboard/KeyboardState.swift").read_text()
        host = HOST.read_text(encoding="utf-8")
        self.assertIn("@Published var keyboardTouchRowsRecoveryRevision = 0", state)
        self.assertEqual(host.count("keyboardTouchRowsRecoveryRevision &+= 1"), 1)
        self.assertIn("self.keyboardState.keyboardAppearanceRevision &+= 1", host)
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
        self.assertIn("onSwipePath: { path in", source)
        self.assertIn("self.swipeTrail.update(path)", source)
        self.assertIn("self.keyboardState.liveDebugAction?(.swipeMoving)", source)
        self.assertNotIn("@State private var liveSwipePath", source)

    def test_system_input_view_and_appearance_time_hosting(self):
        source = HOST.read_text()
        load = source.split("override func loadView()", 1)[1].split("override func updateViewConstraints()", 1)[0]
        self.assertIn("super.loadView()", load)
        self.assertNotIn("self.inputView =", load)
        self.assertNotIn("KeyboardInputView(", source)
        did_load = source.split("override func viewDidLoad()", 1)[1].split("override func viewWillAppear(", 1)[0]
        self.assertNotIn("self.setupKeyboardView()", did_load)
        appear = source.split("override func viewWillAppear(", 1)[1].split("override func viewWillDisappear(", 1)[0]
        self.assertIn("if self.hostingController == nil", appear)
        self.assertLess(appear.index("self.keyboardState.refresh()"), appear.index("self.syncFullAccessIfChanged()"))
        self.assertLess(appear.index("self.syncFullAccessIfChanged()"), appear.index("self.setupKeyboardView()"))
        self.assertIn("UIHostingController<KeyboardView>", source)
        self.assertNotIn("KeyboardHostingRoot", source)
        self.assertIn("hosting.view.bottomAnchor.constraint(equalTo: self.view.bottomAnchor)", source)
        self.assertIn("self.hostingHeightConstraint?.constant = target", source)
        self.assertIn("kind: self.keyboardState.effectiveTypingKind", source)
        self.assertIn("self.view.superview?.layoutIfNeeded()", source)
        self.assertNotIn("controller.rootView =", source)

    def test_height_reconciles_outer_and_host_independently(self):
        source = HOST.read_text(encoding="utf-8")
        height = source.split("private func applyKeyboardHeight()", 1)[1].split(
            "private func makeKeyboardProxy()", 1
        )[0]
        self.assertIn("let outerNeedsUpdate = self.heightConstraint.map", height)
        self.assertIn("let hostingNeedsUpdate = self.hostingHeightConstraint.map", height)
        self.assertIn("guard outerNeedsUpdate || hostingNeedsUpdate else { return }", height)
        self.assertIn("self.heightConstraint?.constant = target", height)
        self.assertIn("self.hostingHeightConstraint?.constant = target", height)
        self.assertNotIn("guard hc.constant != target else { return }", height)

    def test_fixed_heights_and_unified_top_corner_radius(self):
        geometry = (ROOT / "Shared/KeyboardLayoutGeometry.swift").read_text()
        metrics = (ROOT / "SayboardKeyboard/KeyboardMetrics.swift").read_text()
        settings = (ROOT / "Sayboard/Views/KeyboardSettingsView.swift").read_text()
        view = ROOT_VIEW.read_text()
        extended = (ROOT / "SayboardKeyboard/Views/Layouts/ExtendedKeyboardLayout.swift").read_text()
        self.assertIn("static let fullTypingHeight: CGFloat = 277", geometry)
        self.assertIn("static let microphoneCompactHeight: CGFloat = 150", geometry)
        self.assertNotIn("microphoneDefaultHeight", geometry + metrics + settings)
        self.assertIn("KeyboardLayoutGeometry.height(", metrics)
        self.assertIn("KeyboardLayoutGeometry.height(kind: self.kind, microphoneLayout: self.microphoneLayout)", settings)
        self.assertIn("UnevenRoundedRectangle(", view)
        self.assertIn("topLeadingRadius: KeyboardLayoutGeometry.topCornerRadius.kbScaled", view)
        self.assertIn("topTrailingRadius: KeyboardLayoutGeometry.topCornerRadius.kbScaled", view)
        self.assertIn(".ignoresSafeArea(edges: .bottom)", view)
        self.assertIn(".padding(.top, 2.kbScaled)", extended)

    def test_onboarding_preview_uses_fixed_full_height(self):
        preview = (ROOT / "Sayboard/Views/Onboarding/KeyboardLayoutPreview.swift").read_text()
        self.assertIn("KeyboardLayoutGeometry.height(kind: kind, microphoneLayout: .defaultLayout)", preview)
        self.assertNotIn("KeyboardLayoutGeometry.microphoneDefaultHeight", preview)
        self.assertNotIn("static let standardHeight", preview)
        self.assertNotIn("static let extendedHeight", preview)

    def test_fallback_reason_and_diagnostic_writes_are_bounded(self):
        state = (ROOT / "SayboardKeyboard/KeyboardState.swift").read_text()
        host = HOST.read_text(encoding="utf-8")
        trace = (ROOT / "Shared/KeyboardLifecycleTrace.swift").read_text()
        self.assertIn("enum BasicTypingFallbackReason: String, Sendable", state)
        for reason in ("fullAccessUnavailable", "appGroupUnavailable",
                       "microphoneUnavailable", "speechModelUnavailable"):
            self.assertIn("case " + reason, state)
        self.assertIn("self.basicTypingFallbackReason != nil", state)
        self.assertIn("fallbackReason: self.initialStateReady", host)
        self.assertIn("let fallbackReason: String?", trace)
        self.assertIn("fallbackReason: startupReady ? fallbackReason : nil", trace)
        self.assertIn('"schemaVersion": 9', trace)
        self.assertIn('schemaVersion\\":9', trace)
        writes = trace.split("var needsImmediateWrite: Bool", 1)[1].split(
            "var samplesProcessMemory: Bool", 1
        )[0]
        self.assertIn("case .loadViewStarting, .memoryWarning,", writes)
        self.assertIn(".renderSuspicious, .renderRefreshRequested: true", writes)
        for event in (".willAppear", ".willDisappear", ".inputModeChanged",
                      ".hostTextCleared", ".documentIdentifierUnavailable"):
            self.assertNotIn(event, writes)
        self.assertIn("queue.async { append(entry) }", trace)
        self.assertIn("queue.sync { append(entry) }", trace)

    def test_render_probe_distinguishes_blank_root_from_key_rows(self):
        view = ROOT_VIEW.read_text()
        layout = LAYOUT.read_text()
        row = (ROOT / "SayboardKeyboard/Views/AlphabeticTouchRow.swift").read_text()
        diagnostic = (ROOT / "Shared/FeatureDiagnostics.swift").read_text()
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
        self.assertIn("let expectedHeight: Int", lifecycle)
        self.assertIn("expectedHeight: Self.traceDimension(expectedHeight)", host)
        self.assertIn("abs(probe.inputHeight - probe.expectedHeight) > 2", host)
        self.assertIn("abs(probe.hostingHeight - probe.expectedHeight) > 2", host)
        self.assertIn("self.hostGeometry.update(width: width, height: height)", host)
        self.assertNotIn("height: KeyboardMetrics.totalHeight(\n        actionBarVisible:", host.split("override func viewDidLayoutSubviews()", 1)[1].split("let hostValid =", 1)[0])
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

    def test_crash_regression_document_identity_is_optional_at_all_call_sites(self):
        helper = (ROOT / "Shared/KeyboardDocumentIdentifier.swift").read_text()
        trace = (ROOT / "Shared/KeyboardLifecycleTrace.swift").read_text()
        host = HOST.read_text()
        cursor = (ROOT / "SayboardKeyboard/KeyboardViewController+CursorNavigation.swift").read_text()
        live = (ROOT / "SayboardKeyboard/KeyboardViewController+ExperimentalLive.swift").read_text()
        llm = (ROOT / "SayboardKeyboard/KeyboardViewController+LLM.swift").read_text()

        self.assertIn('NSSelectorFromString("documentIdentifier")', helper)
        self.assertIn("proxy.responds(to: selector)", helper)
        self.assertIn("proxy.perform(selector)?.takeUnretainedValue()", helper)
        self.assertIn("object as? NSUUID", helper)
        for source in (host, cursor, live, llm):
            self.assertNotIn("textDocumentProxy.documentIdentifier", source)
            self.assertNotIn("proxy.documentIdentifier", source)

        self.assertIn("let currentDocument = self.availableDocumentIdentifier()", host)
        self.assertIn("KeyboardDocumentIdentifier.isSameOrUnavailable(", host)
        self.assertIn("if currentDocument == nil {", host)
        self.assertIn("self.lastTouchDocumentID = nil", host)
        self.assertIn("self.resetCursorVerticalState()", host)
        self.assertIn("self.recordKeyboardTrace(.documentIdentifierUnavailable)", host)
        self.assertIn("self.recordKeyboardTrace(.documentIdentifierRecovered)", host)
        self.assertIn("guard let document = self.availableDocumentIdentifier() else", cursor)
        self.assertIn("self.resetCursorVerticalState()", cursor)
        self.assertIn("guard let document = self.availableDocumentIdentifier() else", live)
        self.assertIn("self.blockExperimentalLiveChanges(token: update.sessionToken)", live)
        self.assertIn("self.llmDocumentIdentifier != nil", llm)
        self.assertIn("self.availableDocumentIdentifier() == self.llmDocumentIdentifier", llm)
        self.assertIn('"documentIdentityReview": documentIdentityReview(for: events)', trace)
        self.assertNotIn("identifier.uuidString", trace)

    def test_first_build_keyboard_startup_and_input_mode_observability(self):
        host = HOST.read_text(encoding="utf-8")
        trace = (ROOT / "Shared/KeyboardLifecycleTrace.swift").read_text(encoding="utf-8")
        app = (ROOT / "Sayboard/SayboardApp.swift").read_text(encoding="utf-8")
        feature = (ROOT / "Shared/FeatureDiagnostics.swift").read_text(encoding="utf-8")
        self.assertLess(host.index("self.traceFirstKeyboardLoad()"), host.index("super.loadView()"))
        self.assertIn("self.recordKeyboardTrace(.loadViewStarting)", host)
        self.assertIn("canto.keyboardDiagnostics.firstLoadBuildSHA", host)
        self.assertIn("self.firstLoadForBuild == true", host)
        self.assertIn("self.textDocumentProxy.documentInputMode", host)
        self.assertIn("UITextInputMode.activeInputModes", host)
        self.assertIn("UITextInputMode.currentInputModeDidChangeNotification", host)
        self.assertIn("self.recordKeyboardTrace(.inputModeChanged)", host)
        self.assertIn("availableLanguages: Array(available.prefix(16))", host)
        self.assertIn("requestedKeyboardType: self.textDocumentProxy.keyboardType?.rawValue ?? -1", host)
        self.assertIn("case loadViewStarting", trace)
        self.assertIn("case inputModeChanged", trace)
        self.assertIn("let firstLoadForBuild: Bool?", trace)
        self.assertIn("let inputModeProbe: InputModeProbe?", trace)
        self.assertIn('"inputModeReview": inputModeReview(for: events)', trace)
        self.assertIn('"schemaVersion": 9', trace)
        self.assertIn("No callbacks can be guaranteed while iOS runs another keyboard.", trace)
        self.assertIn("FeatureDiagnostics.record(.appStartup, .started)", app)
        self.assertIn("FeatureDiagnostics.record(.appStartup, .completed)", app)
        self.assertIn("area == .appStartup && event == .started", feature)
        for private_content in ("documentContextBeforeInput", "selectedText",
                                "hostBundleId", "touchPath", "audioBuffer"):
            self.assertNotIn(private_content, trace)

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


    def test_live_keyboard_debug_hud_is_independent_bounded_and_private(self):
        hud = (ROOT / "SayboardKeyboard/KeyboardLiveDebugHUD.swift").read_text()
        state = (ROOT / "SayboardKeyboard/KeyboardState.swift").read_text()
        view = HOST.read_text()
        layout = LAYOUT.read_text()
        diagnostics = (ROOT / "Sayboard/Views/DiagnosticsView.swift").read_text()
        constants = (ROOT / "Shared/Constants.swift").read_text()
        self.assertIn("#if !APPSTORE", hud)
        self.assertIn("self.isUserInteractionEnabled = false", hud)
        self.assertIn("self.accessibilityElementsHidden = true", hud)
        self.assertIn("green: 1.0, blue: 0.08", hud)
        self.assertIn("self.events.count - 2", hud)
        self.assertIn("now - self.lastPaintAt >= 0.10", hud)
        self.assertIn("KeyboardLiveDebugHUD(frame: .zero)", view)
        self.assertIn("self.view.bringSubviewToFront(hud)", view)
        self.assertIn("hud.bottomAnchor.constraint(equalTo: self.view.bottomAnchor", view)
        self.assertIn("hud.centerXAnchor.constraint(equalTo: self.view.centerXAnchor)", view)
        self.assertIn("self.liveDebugHUD?.recordLifecycle(", view)
        self.assertIn("liveDebugAction: ((KeyboardLiveDebugAction) -> Void)?", state)
        self.assertIn("self.keyboardState.liveDebugAction?(.swipeMoving)", layout)
        self.assertIn("self.keyboardState.liveDebugAction?(.letterTap)", layout)
        self.assertIn("SharedKey.keyboardLiveDebugHUD", diagnostics)
        self.assertIn('Toggle("Live Keyboard Debug HUD"', diagnostics)
        self.assertIn("keyboardLiveDebugHUD =", constants)
        self.assertIn("?? true", view)
        for forbidden in ("touchPath", "documentContextBeforeInput",
                          "selectedText", "rawTyping", "onInsertText"):
            self.assertNotIn(forbidden, hud)

    def test_host_keyboard_selection_probe_records_only_mode_metadata(self):
        probe = (ROOT / "Sayboard/Views/KeyboardSelectionProbeView.swift").read_text()
        trace = (ROOT / "Shared/KeyboardLifecycleTrace.swift").read_text()
        hud = (ROOT / "SayboardKeyboard/KeyboardLiveDebugHUD.swift").read_text()
        host = HOST.read_text()
        diagnostics = (ROOT / "Sayboard/Views/DiagnosticsView.swift").read_text()
        self.assertIn("#if !APPSTORE", probe)
        self.assertIn("NavigationLink(\"Keyboard Selection Probe\")", diagnostics)
        self.assertIn("UITextInputMode.currentInputModeDidChangeNotification", probe)
        self.assertIn("UIResponder.keyboardDidShowNotification", probe)
        self.assertIn("field.textInputMode?.primaryLanguage", probe)
        self.assertIn("override var textInputContextIdentifier: String?", probe)
        self.assertIn("UIResponder.clearTextInputContextIdentifier", probe)
        self.assertIn("KeyboardLifecycleTrace.recordHostInputMode(", probe)
        self.assertIn("let hostInputMode: HostSelectionSnapshot", trace)
        self.assertIn("private static func hostSelectionReview", trace)
        self.assertIn("queue.async { append(entry) }", trace)
        self.assertIn("startupReady: self.initialStateReady", host)
        self.assertIn("fallback: startupReady && requestedMode != effectiveMode", trace)
        self.assertIn("runtimeLanguage: self.primaryLanguage", host)
        self.assertNotIn("AB mis", hud)
        self.assertIn('"schemaVersion": 9', trace)
        for forbidden in ("documentContextBeforeInput", "selectedText",
                          "touchPath", "textField.text =", "field.text ="):
            self.assertNotIn(forbidden, probe)

    def test_handoff_monitor_is_exported_without_private_input(self):
        trace = (ROOT / "Shared/KeyboardLifecycleTrace.swift").read_text()
        analyzer = (ROOT / "Shared/KeyboardHandoffAnalyzer.swift").read_text()
        probe = (ROOT / "Sayboard/Views/KeyboardSelectionProbeView.swift").read_text()
        diagnostics = (ROOT / "Sayboard/Views/DiagnosticsView.swift").read_text()
        workflow = (ROOT / ".github/workflows/build-unsigned-ipa.yml").read_text()
        self.assertIn("private static func handoffReview(for events:", trace)
        self.assertIn('"handoffReview": handoffReview(for: events)', trace)
        self.assertIn("KeyboardHandoffAnalyzer.analyze(", trace)
        self.assertIn("static func handoffReview() -> [String: Any]", trace)
        self.assertIn("modeChangedAwayBeforeLoad", analyzer)
        self.assertIn("extensionDetectedFieldUnconfirmed", analyzer)
        self.assertIn('language == "mul" || language == "mis"', trace)
        self.assertIn(".hostLanguageHint", trace)
        self.assertNotIn(".hostMis", trace)
        self.assertIn("case hostLanguageHint, hostOther, fieldEnded", analyzer)
        self.assertIn("signal.kind == .fieldEnded", analyzer)
        self.assertIn("signal.activationID != activationID", analyzer)
        self.assertIn("let activationID = snapshot[\"activationID\"] as? String", trace)
        self.assertIn("self.activeActivationID = UUID().uuidString", probe)
        self.assertIn("activationID: self.activeActivationID", probe)
        self.assertIn("Extension detected; field unconfirmed", probe)
        self.assertNotIn("case mountedObserved", analyzer)
        self.assertIn("launchNotObserved", analyzer)
        self.assertIn("an input-mode language identifies the keyboard on screen", analyzer)
        self.assertIn('NavigationLink("Handoff Monitor")', diagnostics)
        self.assertIn("KeyboardLifecycleTrace.handoffReview()", probe)
        self.assertIn("struct KeyboardHandoffMonitorView: View", probe)
        self.assertIn("scripts/verify-keyboard-handoff.swift", workflow)
        self.assertIn('"schemaVersion": 9', trace)
        self.assertIn('schemaVersion\\":9', trace)
        for private_content in ("documentContextBeforeInput", "selectedText",
                                "touchPath", "textField.text ="):
            self.assertNotIn(private_content, analyzer)

    def test_multilingual_primary_language_and_interface_fallback(self):
        import plistlib

        info = plistlib.loads((ROOT / "SayboardKeyboard/Info.plist").read_bytes())
        attributes = info["NSExtension"]["NSExtensionAttributes"]
        self.assertEqual(attributes["PrimaryLanguage"], "mul")
        self.assertTrue(attributes["IsASCIICapable"])
        controller = HOST.read_text(encoding="utf-8")
        self.assertNotIn("self.primaryLanguage =", controller)

        app = (ROOT / "Sayboard/SayboardApp.swift").read_text(encoding="utf-8")
        constants = (ROOT / "Shared/Constants.swift").read_text(encoding="utf-8")
        settings = (ROOT / "Sayboard/Views/SettingsView.swift").read_text(encoding="utf-8")
        self.assertIn('static let fallback = "en"', constants)
        self.assertIn("AppLanguageConfig.resolveLanguage(from: Locale.preferredLanguages)", app)
        self.assertIn("if let current = defaults.string(forKey: SharedKey.appLanguage)", app)
        self.assertIn("AppLanguageListView()", settings)


if __name__ == "__main__":
    unittest.main()



