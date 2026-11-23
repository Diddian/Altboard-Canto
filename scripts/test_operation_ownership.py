from pathlib import Path
import unittest

ROOT = Path(__file__).resolve().parent.parent


def source(path):
    return (ROOT / path).read_text()


def function(path, name, next_name=None):
    text = source(path).split(name, 1)[1]
    return text.split(next_name, 1)[0] if next_name else text


class OperationOwnershipTests(unittest.TestCase):
    def test_cold_model_audio_recovery_keeps_session_intent_and_stop_gate(self):
        audio = source("Sayboard/Services/BackgroundAudioSession.swift")
        speech = source("Sayboard/Services/SpeechRecognitionService.swift")
        diagnostics = source("Shared/FeatureDiagnostics.swift")
        suspended = function("Sayboard/Services/BackgroundAudioSession.swift",
                             "func suspendForModelLoad()", "func restoreAfterModelLoad(")
        resumed = function("Sayboard/Services/BackgroundAudioSession.swift",
                           "func restoreAfterModelLoad(", "/// Single capture gate")
        stop = function("Sayboard/Services/SpeechRecognitionService.swift",
                        "func stopRecording()", "func cancelRecording()")
        ending = function("Sayboard/Services/BackgroundAudioSession.swift",
                          "func endSession()", "private func finishParkedSession()")
        self.assertIn("self.recoveryGate.park(", suspended)
        self.assertNotIn("self.endSession()", suspended)
        self.assertIn("self.recoveryGate.cancel()", ending)
        self.assertIn("self.recoveryGate.take(", resumed)
        self.assertIn("playbackFree: Self.playbackOwner == nil", resumed)
        self.assertIn("competingSessionFree: Self.activeSession == nil || Self.activeSession === self", resumed)
        self.assertIn("self.closeActiveSession(notifyEnded: false)", suspended)
        self.assertIn("if notifyEnded { self.onSessionEnded?() }", audio)
        self.assertIn("if self.recoveryGate.isParked {", audio)
        self.assertIn("try self.startSession()", resumed)
        self.assertNotIn("self.session.suspendForModelLoad()", stop)
        self.assertNotIn("self.session.endSession()", stop)
        self.assertIn("self.activeDictationToken == finalizationToken", stop)
        self.assertIn("self.isCurrentDictation(finalizationToken)", stop)
        self.assertIn("audioSessionRestoreFailed", diagnostics)
        self.assertIn("self.session.isSessionHealthy", speech)
        self.assertIn("LiveWarmupMemoryPolicy.allowsWarmup(", speech)
        self.assertIn("releaseInactiveSpeechEnginesForQwen()", speech)
        self.assertIn("TranscriptionBridge.postDarwinNotification(DarwinNotificationName.dictationStopped)", stop)
        reload = function("Sayboard/Services/SpeechRecognitionService.swift",
                          "func reloadModel(", "private func restoreParkedAudioSession(")
        self.assertIn("self.session.suspendForModelLoad()", reload)
        self.assertIn("self.restoreParkedAudioSession(allowed: !self.isRecording)", reload)
        self.assertIn("private func restoreParkedAudioSession(", speech)
        deactivate = function("Sayboard/Services/SpeechRecognitionService.swift",
                              "func deactivateCompletely()", "func startRecordingAfterModelLoad()")
        self.assertLess(deactivate.index("self.session.endSession()"),
                        deactivate.index("await self.unloadAllEngines()"))

    def test_stale_audio_flag_requires_running_engine_before_capture(self):
        audio = source("Sayboard/Services/BackgroundAudioSession.swift")
        speech = source("Sayboard/Services/SpeechRecognitionService.swift")
        activation = function("Sayboard/Services/BackgroundAudioSession.swift",
                              "func startSession() throws", "func endSession()")
        health = function("Sayboard/Services/BackgroundAudioSession.swift",
                          "var isSessionHealthy:", "nonisolated let levelBridge")
        self.assertIn("self.audioEngine.isRunning", health)
        self.assertIn("Self.activeSession === self", health)
        self.assertIn("guard !self.isSessionHealthy else { return }", activation)
        ensure = function("Sayboard/Services/SpeechRecognitionService.swift",
                          "private func ensureSessionActive()", "private func startAudioCapture()")
        self.assertIn("guard !self.session.isSessionHealthy", ensure)
        self.assertIn("return self.session.isSessionHealthy", ensure)
        self.assertIn("let sessionStartedHere = !self.session.isSessionHealthy", speech)
        self.assertIn("self.activeSession?.isSessionHealthy != true", audio)

    def test_warm_session_uses_recent_audio_liveness_before_app_jump(self):
        policy = source("Shared/DictationRequestPolicy.swift")
        source_method = function("Shared/DictationRequestPolicy.swift",
                                 "static func shouldRequestWarmSession(", "static func shouldOpenColdFallback(")
        self.assertIn("practiceFocused || appActive || keyboardActive || modelLoading", source_method)
        self.assertIn("|| hasRecentAudioHeartbeat(heartbeat, now: now)", source_method)
        controller = source("SayboardKeyboard/KeyboardViewController.swift")
        self.assertIn("self.scheduleWarmStartCheck(", controller)
        self.assertIn("token: token, retryCount: 0,", controller)
        self.assertIn("!appAcknowledged", policy)
        self.assertIn("&& keyboardVisible && !recording && !appAcknowledged", policy)
        self.assertIn("timeout: direct ? Self.staleFallbackTimeout : 0.8", controller)

    def test_live_preview_has_no_host_mutation(self):
        live = source("SayboardKeyboard/KeyboardViewController+ExperimentalLive.swift")
        self.assertIn("self.keyboardState.liveSourcePreview =", live)
        for mutation in ("textDocumentProxy", "insertText(", "deleteBackward("):
            self.assertNotIn(mutation, live)

    def test_haptic_recovery_is_idempotent_and_uses_direct_uikit_fallback(self):
        haptic = source("Shared/KeyboardHaptics.swift")
        controller = source("SayboardKeyboard/KeyboardViewController.swift")
        self.assertIn("private static var prepared = false", haptic)
        self.assertIn("guard !prepared else { return }", haptic)
        self.assertIn('KeyboardHapticTrace.record(technique: "core->uikit"', haptic)
        self.assertIn("triggerUIKit(technique: .automatic, strength: strength)", haptic)
        self.assertIn('KeyboardHapticTrace.record(technique: "core->sensory"', haptic)
        self.assertIn("sensoryViewOwner != nil", haptic)
        self.assertIn("setSensoryViewReady(true, owner: self.keyboardState)",
                      source("SayboardKeyboard/Views/KeyboardView.swift"))
        self.assertIn("if prepared { suspend() }", haptic)
        did_load = function("SayboardKeyboard/KeyboardViewController.swift",
                            "override func viewDidLoad()", "override func viewWillAppear(")
        self.assertNotIn("KeyboardHaptics.prepare(owner: self)", did_load)
        self.assertIn("KeyboardHaptics.prepare(owner: self)", controller)
        self.assertIn("KeyboardHaptics.suspend(owner: self)", controller)
        self.assertIn("activeOwner != ObjectIdentifier(owner)", haptic)

    def test_warm_session_diagnostics_explain_rearm_without_new_owner(self):
        speech = source("Sayboard/Services/SpeechRecognitionService.swift")
        controller = source("SayboardKeyboard/KeyboardViewController.swift")
        diagnostics = source("Shared/FeatureDiagnostics.swift")
        self.assertIn("case coldAudioSessionStart, warmStartUnacknowledged", diagnostics)
        self.assertIn("case destinationUnavailable, destinationChanged, destinationOwnerLost", diagnostics)
        self.assertIn("sessionStartedHere ? .fallback : .selected", speech)
        start = function("SayboardKeyboard/KeyboardViewController.swift",
                         "private func startDictationViaDarwin()",
                         "private func scheduleWarmStartCheck(")
        self.assertIn("settings.isRecording && settings.isSessionActive", start)
        self.assertIn("self.recoverActiveDictationAfterReentry()", start)
        self.assertIn("self.verifyReenteredRecording(token: token)", start)
        self.assertIn("DictationRequestPolicy.shouldRestartUnacknowledgedRecording(", start)
        self.assertIn("!self.warmStartSessionAcknowledged", start)
        self.assertIn("self.pingMainAppForSessionStatus()", start)
        self.assertNotIn("failureReason: .coldAudioSessionStart", start)
        self.assertIn("self.scheduleWarmStartCheck(", start)
        schedule = function("SayboardKeyboard/KeyboardViewController.swift",
                            "private func scheduleWarmStartCheck(",
                            "private func openDictateDeepLinkFallback(")
        self.assertIn("failureReason: .warmStartUnacknowledged", schedule)
        self.assertIn("private func currentDictationFocus()", controller)
        self.assertIn("self.insertSpacedText(text)", controller)

    def test_cold_app_launch_keeps_valid_host_dictation_token(self):
        app = source("Sayboard/SayboardApp.swift")
        policy = source("Shared/DictationRequestPolicy.swift")
        app_init = app.split("struct SayboardApp: App {", 1)[1].split(
            "@UIApplicationDelegateAdaptor", 1
        )[0]
        self.assertIn("shouldPreserveColdStartRequest(", policy)
        self.assertIn("isRecentKeyboardRequest: settings.isKeyboardRequestRecent()", app_init)
        self.assertIn("token: settings.dictationSessionToken", app_init)
        self.assertIn("if !preserveColdRequest {", app_init)
        self.assertIn("settings.dictationSessionToken = nil", app_init)
        self.assertIn("settings.dictationDestinationEpoch = nil", app_init)
        self.assertIn("operationID: preservedToken, phase: .accepted", app_init)
        self.assertEqual(app_init.count("settings.dictationSessionToken = nil"), 1)
        service = source("Sayboard/Services/SpeechRecognitionService+Transcription.swift")
        self.assertIn("self.currentTranscription = finalOutput", service)
        controller = source("SayboardKeyboard/KeyboardViewController.swift")
        self.assertIn("self.insertDeferredAppearanceText()", controller)
        self.assertIn("self.insertSpacedText(text)", controller)

    def test_keyboard_reentry_requires_live_capture_acknowledgment(self):
        state = function("SayboardKeyboard/KeyboardState.swift", "func refresh()", "func syncVoiceProcessingProgress()")
        self.assertNotIn("self.isRecording = self.settings.isRecording", state)
        recovery = function("SayboardKeyboard/KeyboardViewController.swift", "func recoverActiveDictationAfterReentry()", "private func startDictationViaDarwin()")
        self.assertNotIn("self.keyboardState.isRecording = settings.isRecording", recovery)
        self.assertNotIn("self.beginFreshDictation()", recovery)
        observer = function("SayboardKeyboard/KeyboardViewController.swift", "Self.dictationStartedObserver =", "Self.dictationStoppedObserver =")
        self.assertLess(observer.index("vc.recoverActiveDictationAfterReentry()"), observer.index("DictationRequestPolicy.mayShowRecording("))
        self.assertLess(observer.index("DictationRequestPolicy.mayShowRecording("), observer.index("vc.keyboardState.isRecording = true"))
        self.assertLess(observer.index("guard !vc.keyboardState.isProcessing"), observer.index("vc.keyboardState.isRecording = true"))

    def test_capture_acknowledgment_requires_frames_and_defers_early_stop(self):
        start = function("Sayboard/Services/SpeechRecognitionService.swift", "func startCapture()", "private func awaitCaptureConfirmation()")
        self.assertNotIn("self.settings.isRecording = true", start)
        self.assertIn("self.currentWordBoundaries = nil", start)
        self.assertIn("self.awaitCaptureConfirmation()", start)
        ack = function("Sayboard/Services/SpeechRecognitionService.swift", "private func acknowledgeCaptureIfReady()", "private func failUnconfirmedCapture(")
        self.assertLess(ack.index("self.session.captureConfirmation(owner: .dictation) == .confirmed"), ack.index("self.settings.isRecording = true"))
        self.assertIn("self.activeDictationToken == token", ack)
        self.assertIn("MicrophoneHoldStopIntent.consume(", ack)
        service = source("Sayboard/Services/SpeechRecognitionService.swift")
        self.assertIn("DictationCapturePolicy.shouldDeferRequestedStop(", service)
        self.assertIn("self.captureConfirmationTask != nil", service)

    def test_finalization_is_not_recording_or_an_unbounded_storage_lock(self):
        stop = function("Sayboard/Services/SpeechRecognitionService.swift", "func stopRecording()", "func cancelRecording()")
        self.assertLess(stop.index("self.settings.isRecording = false"), stop.index("TranscriptionBridge.writeVoiceProgress(.stoppingAudio)"))
        busy = function("Sayboard/Services/LocalUserDataStore.swift", "static var hasActiveOperation:", "static let learnedKeys")
        self.assertIn("DictationCapturePolicy.isPendingStart(", busy)
        self.assertIn("TranscriptionBridge.readVoiceProgress()?.isCurrent(", busy)
        rejection = function("Sayboard/Services/SpeechRecognitionService.swift", "private func rejectUnacceptedDictationRequest(", "func startCapture()")
        self.assertIn("DictationCapturePolicy.canRejectUnacceptedRequest(", rejection)
        self.assertIn("self.settings.dictationSessionToken = nil", rejection)
        self.assertNotIn("self.session.endSession()", rejection)
        self.assertNotIn("TranscriptionBridge.clearTranscription()", rejection)

    def test_all_voice_progress_stages_stop_the_capture_presentation(self):
        progress = function("SayboardKeyboard/KeyboardState.swift", "func syncVoiceProcessingProgress()", "func syncModelLoading()")
        self.assertIn("update.isCurrent(", progress)
        self.assertNotIn("update.stage == .stoppingAudio", progress)
        self.assertIn("self.isRecording = false", progress)
        self.assertIn("self.isProcessing = true", progress)
        self.assertIn("self.stopLevelPolling()", progress)
        observer = function("SayboardKeyboard/KeyboardViewController.swift", "private func setupVoiceProgressObserver()", "private func setupInputModeObserver()")
        self.assertIn("vc.resumeProcessingTimeoutIfNeeded()", observer)

    def test_processing_polls_durable_results_before_timeout_cancellation(self):
        resume = function("SayboardKeyboard/KeyboardViewController+Timeout.swift", "func resumeProcessingTimeoutIfNeeded()", "func cancelProcessingTimeout()")
        self.assertLess(resume.index("guard self.viewIfLoaded?.window != nil"), resume.index("self.startProcessingTimeout()"))
        self.assertLess(resume.index("guard self.processingTimeoutTimer?.isValid != true"), resume.index("self.startProcessingTimeout()"))
        timeout = function("SayboardKeyboard/KeyboardViewController+Timeout.swift", "func startProcessingTimeout()", "func resetProcessingState()")
        self.assertLess(timeout.index("self.insertTranscribedText()"), timeout.index("if self.receivedPingDuringProcessing"))
        self.assertLess(timeout.index("self.finalizeProcessingPipeline()"), timeout.index("self.cancelDictationViaDarwin()"))
        self.assertIn("guard self.viewIfLoaded?.window != nil", timeout)
        self.assertIn("self.processingTimeoutGeneration == generation", timeout)
        self.assertLess(timeout.index("self.processingTimeoutTimer = nil"), timeout.index("guard self.viewIfLoaded?.window != nil", timeout.index("Timer.scheduledTimer")))
        insertion = function("SayboardKeyboard/KeyboardViewController.swift", "func insertTranscribedText()", "func pingMainAppForSessionStatus()")
        self.assertLess(insertion.index("guard self.dictationStartupVisible, self.viewIfLoaded?.window != nil"), insertion.index("self.insertSpacedText(text)"))
        self.assertIn("defer { self.refreshRecoverableLLMResult() }", insertion)
        observer = function("SayboardKeyboard/KeyboardViewController.swift", "private func setupTranscriptionObserver()", "private func setupVoiceProgressObserver()")
        self.assertIn("if vc.insertTranscribedText()", observer)
        self.assertNotIn("vc.cancelProcessingTimeout()", observer)

    def test_early_release_requires_a_matching_unconfirmed_stop_before_recovery(self):
        controller = source("SayboardKeyboard/KeyboardViewController.swift")
        stop = controller.split("func stopDictationViaDarwin()", 1)[1].split(
            "private func setupSessionLifecycleObservers()", 1)[0]
        self.assertIn("isStartingRecording && !self.warmStartSessionAcknowledged", stop)
        self.assertIn("self.stoppedBeforeCaptureToken = self.dictationRequestToken", stop)
        ack = controller.split("Self.dictationStartedObserver =", 1)[1]
        self.assertLess(ack.index("mayShowRecording("), ack.index("vc.stoppedBeforeCaptureToken = nil"))
        timer = source("SayboardKeyboard/KeyboardViewController+Timeout.swift")
        check = timer.split("elapsed >= 15", 1)[1].split("return", 1)[0]
        for guard in ("token == self.dictationRequestToken", "current: settings.dictationSessionToken",
                      "!settings.isRecording", "!settings.isModelLoading", "!self.receivedPingDuringProcessing",
                      "hasRecentAudioHeartbeat", "readVoiceProgress()?.isCurrent"):
            self.assertIn(guard, check)
        self.assertIn("failureReason: .audioCaptureUnconfirmed, operationID: token", check)
        self.assertIn("self.keyboardState.dictationOutcome = .activationFailed", check)

    def test_idle_microphone_unmounts_repeating_animations(self):
        mic = source("SayboardKeyboard/Views/Layouts/MicAnimatedButton.swift")
        self.assertRegex(mic, r"if isSpin \{\s+TwoDotOrbitProcessing")
        self.assertIn("if show { pulse }", mic)
        self.assertIn(".frame(width: pulse.maxWidth, height: pulse.maxHeight)", mic)

    def test_mic_animation_reentry_invalidates_old_completions(self):
        mic = source("SayboardKeyboard/Views/Layouts/MicAnimatedButton.swift")
        self.assertIn("generation == self.animationGeneration", mic)
        self.assertIn("self.isVisible = false", mic)
        self.assertIn("self.resetMicTransitions()", mic)
        idle = mic.split("let isIdle =", 1)[1].split("ZStack", 1)[0]
        self.assertNotIn("pendingSpinnerMorph", idle)
        morph = source("SayboardKeyboard/Views/MicMorphAnimation.swift")
        self.assertIn(".onChange(of: self.direction)", morph)
        self.assertIn("self.isComplete = false", morph)

    def test_final_delivery_keeps_pending_result_on_destination_mismatch(self):
        body = function("SayboardKeyboard/KeyboardViewController.swift", "func insertTranscribedText()", "func pingMainAppForSessionStatus")
        self.assertLess(body.index("delivery.canInsert"), body.index("acknowledgeDelivery"))
        self.assertNotIn("clearTranscription()", body)

    def test_scoped_delivery_cannot_return_a_foreign_pending_result(self):
        body = function("Shared/TranscriptionBridge.swift", "static func readDelivery(", "static func readTranscription()")
        self.assertIn("if let token, result.sessionToken == token", body)
        self.assertIn("return token == nil && destinationEpoch == nil ? latest : nil", body)
        observer = function("SayboardKeyboard/KeyboardViewController.swift",
                            "Self.dictationStoppedObserver =", "self.setupSessionLifecycleObservers()")
        self.assertIn("vc.insertTranscribedText()", observer)
        self.assertNotIn("TranscriptionBridge.readTranscription()", observer)

    def test_dismissal_and_cursor_changes_revoke_auto_insert(self):
        controller = source("SayboardKeyboard/KeyboardViewController.swift")
        for callback in ("override func viewWillDisappear", "private func hostDidEnterBackground"):
            self.assertIn("self.dictationFocus = nil", controller.split(callback, 1)[1].split("\n  }", 1)[0])
        for callback in ("override func textDidChange", "override func selectionDidChange"):
            self.assertIn("self.invalidateChangedDictationFocus()", controller.split(callback, 1)[1].split("\n  }", 1)[0])
        recovery = controller.split("func recoverActiveDictationAfterReentry()", 1)[1].split("private func startDictationViaDarwin()", 1)[0]
        self.assertNotIn("self.dictationFocus = self.currentDictationFocus()", recovery)

    def test_documentless_and_history_cross_field_mutations_fail_closed(self):
        policy = source("Shared/DictationRequestPolicy.swift")
        keyboard = source("SayboardKeyboard/KeyboardViewController.swift")
        llm = source("SayboardKeyboard/KeyboardViewController+LLM.swift")
        state = source("SayboardKeyboard/KeyboardState.swift")
        self.assertNotIn("mayDeliverWithoutDocumentIdentifier(", policy + keyboard)
        self.assertIn("static func originProcessMarker(", policy)
        self.assertIn("let document = self.availableDocumentIdentifier() else { return nil }", keyboard)
        self.assertIn("self.keyboardState.llmHistoryDocumentIdentifier", llm)
        self.assertIn("self.availableDocumentIdentifier() == origin", llm)
        self.assertIn("self.keyboardState.llmHistoryEpoch == self.keyboardState.documentEpoch", llm)
        self.assertIn("self.llmHistoryDocumentIdentifier = nil", state)

    def test_corrupt_history_keeps_new_audio_and_migration_retries(self):
        history = source("Shared/HistoryStore.swift")
        migration = source("Sayboard/Services/LegacyModelMigration.swift")
        save = function("Shared/HistoryStore.swift", "func saveRecord(", "func saveCorrectedTranscript(")
        self.assertIn("self.preserveUnindexedRecord(record)", save)
        self.assertIn("FeatureDiagnostics.record(.data, .fallback)", save)
        self.assertEqual(save.count("self.deleteAudioFile(named: record.audioFileName)"), 1)
        self.assertIn("unindexed-\\(record.id.uuidString).json", history)
        self.assertIn("guard whisperComplete && parakeetComplete else", migration)
        self.assertIn("if ModelStorageManager.isDownloaded(variant)", migration)
        self.assertLess(migration.index("guard whisperComplete && parakeetComplete else"),
                        migration.index('defaults.set(true, forKey: migrationKey)'))

    def test_146_style_automatic_callbacks_keep_scoped_delivery(self):
        controller = source("SayboardKeyboard/KeyboardViewController.swift")
        insert = function("SayboardKeyboard/KeyboardViewController.swift",
                          "func insertTranscribedText()", "func pingMainAppForSessionStatus")
        self.assertIn("self.dictationFocus?.matches(self.currentDictationFocus())", insert)
        self.assertIn("self.dictationRequestToken.flatMap { token in", insert)
        self.assertIn("matching: token, allowAnyDestination: true", insert)
        self.assertNotIn("defer { TranscriptionBridge.acknowledgeDelivery", insert)
        self.assertIn("let matchesDocument = delivery.canInsert(", insert)
        self.assertNotIn("matchesDocumentlessHost", insert)
        self.assertIn("matchesDocument else {", insert)
        self.assertLess(insert.index("delivery.canInsert"), insert.index("TranscriptionBridge.acknowledgeDelivery"))
        self.assertIn("self.insertSpacedText(text)", insert)
        self.assertIn("TranscriptionBridge.acknowledgeDelivery(delivery.resultID)", insert)
        self.assertIn("TranscriptionBridge.cancellationToken() != delivery.sessionToken", controller)
        self.assertNotIn("func insertPendingDictation()", controller)
        self.assertNotIn("refreshPendingDictation()", controller)

    def test_outbox_is_consumed_before_automatic_proxy_write(self):
        handling = function("SayboardKeyboard/KeyboardViewController.swift",
                            "func insertTranscribedText()", "func pingMainAppForSessionStatus")
        claim = handling.index("guard TranscriptionBridge.acknowledgeDelivery(delivery.resultID)")
        self.assertLess(handling.index("matchesDocument else"), claim)
        self.assertLess(claim, handling.index("self.insertSpacedText(text)"))

    def test_completed_ai_request_does_not_send_failure_notification(self):
        body = function("Sayboard/Services/LLMProcessingCoordinator.swift",
                        "private func handleProcessingRequest()", "private func beginInferenceBackgroundTask()")
        self.assertIn("if terminalPhase != .completed", body)
        self.assertEqual(body.count("DarwinNotificationName.llmProcessingFailed"), 3)
        validation = function("Sayboard/Services/LLMProcessingCoordinator.swift",
                              "private func validateRequest", "private func beginInferenceBackgroundTask")
        self.assertNotIn("DarwinNotificationName.llmProcessingFailed", validation)

    def test_cancel_observer_checks_the_active_token(self):
        body = function("Sayboard/Services/SpeechRecognitionService.swift", "self.requestCancelObserver =", "self.requestStopObserver =")
        self.assertLess(body.index("OperationPolicy.ownsCancellation"), body.index("self.cancelRecording()"))

    def test_cancellation_releases_capture_without_releasing_session(self):
        body = function("Sayboard/Services/SpeechRecognitionService.swift", "func cancelRecording()", "func transcribeSamples")
        self.assertIn("self.session.endCapture(owner: .dictation)", body)
        self.assertNotIn("self.session.endSession()", body)
        self.assertIn("self.finalizationTask?.cancel()", body)
        self.assertIn("self.experimentalLiveTask?.cancel()", body)
        self.assertNotIn("await ", body)

    def test_start_stop_finalization_uses_owned_session_and_explicit_failure_paths(self):
        service = source("Sayboard/Services/SpeechRecognitionService.swift")
        capture = function("Sayboard/Services/SpeechRecognitionService.swift",
                           "func startCapture()", "func scheduleQwenWarmupAfterCapture")
        stop = function("Sayboard/Services/SpeechRecognitionService.swift",
                        "func stopRecording()", "func cancelRecording")
        final = function("Sayboard/Services/SpeechRecognitionService+Transcription.swift",
                         "func runFinalTranscription(", "func saveHistoryRecord(")
        self.assertLess(capture.index("!self.settings.dictationCancellationRequested"),
                        capture.index("try self.startAudioCapture()"))
        self.assertLess(stop.index("while (self.speechWorkers > 0"),
                        stop.index("await self.runFinalTranscription("))
        self.assertLess(stop.index("self.session.endCapture(owner: .dictation)"),
                        stop.index("await self.stopExperimentalLive()"))
        self.assertLess(stop.index("guard self.isCurrentDictation(finalizationToken) else { return }"),
                        stop.index("await self.runFinalTranscription("))
        self.assertIn("case .noSpeech:", final)
        self.assertIn("self.settings.lastDictationOutcome = .noSpeech", final)
        self.assertIn("case .failed:", final)
        self.assertIn("self.settings.lastDictationOutcome = .engineFailed", final)
        self.assertIn("guard !samples.isEmpty else", final)
        self.assertIn("self.settings.lastDictationOutcome = .engineFailed", final)
        self.assertIn("if case .text(let output) = result", final)
        self.assertLess(stop.index("await self.runFinalTranscription("),
                        stop.index("self.saveHistoryRecord(preserveUntranscribedAudio: retainUndecodedAudio)"))
        self.assertIn("TranscriptionBridge.postDarwinNotification(DarwinNotificationName.dictationStopped)", stop)
        self.assertIn("func transcribeSamples(_ samples:", service)

    def test_cancel_rejects_stale_publication_and_preserves_failed_asr_audio(self):
        service = source("Sayboard/Services/SpeechRecognitionService.swift")
        stop = function("Sayboard/Services/SpeechRecognitionService.swift",
                        "func stopRecording()", "func cancelRecording")
        cancel = function("Sayboard/Services/SpeechRecognitionService.swift",
                          "func cancelRecording()", "func transcribeSamples")
        final = function("Sayboard/Services/SpeechRecognitionService+Transcription.swift",
                         "func runFinalTranscription(", "func saveHistoryRecord(")
        history = function("Sayboard/Services/SpeechRecognitionService+Transcription.swift",
                           "func saveHistoryRecord(")
        live = source("Sayboard/Services/SpeechRecognitionService+ExperimentalLive.swift")
        self.assertIn("let retainUndecodedAudio = self.settings.lastDictationOutcome == .engineFailed", stop)
        self.assertIn("|| self.settings.lastDictationOutcome == .processingFailed", stop)
        self.assertIn("self.saveHistoryRecord(preserveUntranscribedAudio: retainUndecodedAudio)", stop)
        self.assertIn("saveHistoryRecord(preserveUntranscribedAudio: true)", stop)
        self.assertIn("preserveUntranscribedAudio && recognized.isEmpty", history)
        self.assertIn("if result.writeFailed", history)
        self.assertIn("guard !transcription.isEmpty else", history)
        self.assertIn("self.settings.dictationSessionToken = nil", cancel)
        self.assertIn("self.settings.dictationCancellationRequested = true", cancel)
        self.assertIn("ExperimentalLiveTranscription.clear()", cancel)
        self.assertIn("matching: token, allowAnyDestination: true, includeUncommitted: true", cancel)
        self.assertIn("guard self.isCurrentDictation(requestToken) else { return }", final)
        self.assertIn("guard !Task.isCancelled, self.isRecording else { break }", live)
        self.assertIn("if ExperimentalLiveTranscription.write(", live)

    def test_retry_records_before_old_decoder_releases_model(self):
        start = function("Sayboard/Services/SpeechRecognitionService.swift", "func startCapture()", "private func awaitCaptureConfirmation")
        self.assertNotIn("self.speechWorkers", start)
        finish = function("Sayboard/Services/SpeechRecognitionService.swift", "private func finishRecording", "func cancelRecording()")
        self.assertIn("let deadline = clock.now.advanced(by: .seconds(15))", finish)
        self.assertLess(finish.index("while (self.speechWorkers > 0"), finish.index("await self.runFinalTranscription("))
        decode = function("Sayboard/Services/SpeechRecognitionService.swift", "func transcribeSamples", "func loadModelIfAvailable")
        self.assertIn("defer { self.speechWorkers -= 1 }", decode)

    def test_cold_and_warm_microphone_share_one_request_owner(self):
        controller = source("SayboardKeyboard/KeyboardViewController.swift")
        mic = function("SayboardKeyboard/Views/Layouts/MicAnimatedButton.swift",
                       "private func handleTap()", "private func handleRecordingChanged")
        start = function("SayboardKeyboard/KeyboardViewController.swift",
                         "private func startDictationViaDarwin()", "private func scheduleWarmStartCheck")
        self.assertIn("self.proxy.startDictation()", mic)
        self.assertNotIn("settings.dictationSessionToken = UUID()", mic)
        self.assertNotIn("DeepLink.dictateURL", mic)
        self.assertIn("self.prepareDictationDestination()", start)
        self.assertIn("TranscriptionBridge.postDarwinNotification(DarwinNotificationName.requestStartDictation)", start)
        self.assertIn("self.scheduleWarmStartCheck(", start)
        self.assertNotIn("self.openDictateDeepLinkFallback(", start)
        self.assertIn('self.openDictateDeepLinkFallback(reason: "no active audio engine")', controller)
        self.assertIn("self.recoverActiveDictationAfterReentry()", start)
        self.assertIn("self.keyboardState.isStartingRecording = true", start)
        self.assertIn("self.recoverActiveDictationAfterReentry()", controller)

    def test_recreated_keyboard_can_stop_without_claiming_another_field(self):
        controller = source("SayboardKeyboard/KeyboardViewController.swift")
        settings = source("Shared/SharedSettings.swift")
        bridge = source("Shared/TranscriptionBridge.swift")
        service = source("Sayboard/Services/SpeechRecognitionService.swift")
        restore = function("SayboardKeyboard/KeyboardViewController.swift",
                           "func recoverActiveDictationAfterReentry()", "private func startDictationViaDarwin")
        self.assertIn("DictationRequestPolicy.isSameDestination(", restore)
        self.assertIn("self.dictationDocumentID = nil", restore)
        self.assertIn("self.dictationFocus = nil", restore)
        self.assertIn("self.keyboardState.documentEpoch = epoch", restore)
        self.assertIn("func stopDictationViaDarwin()", controller)
        self.assertIn("TranscriptionBridge.requestStop(for: self.dictationRequestToken)", controller)
        self.assertIn("TranscriptionBridge.requestCancellation(for: cancelled)", controller)
        self.assertIn("settings.dictationDestinationFingerprint = nil", controller)
        self.assertIn("var dictationDestinationFingerprint: String?", settings)
        self.assertIn("allowAnyDestination || result.destinationEpoch == destinationEpoch", bridge)
        self.assertIn("guard self.activeDictationToken == self.settings.dictationSessionToken", service)
        self.assertIn("self.dictationDocumentID != nil", controller)
        self.assertIn("DictationRequestPolicy.isSameDestination(", controller)

    def test_extension_timeout_cannot_reset_host_runtime(self):
        body = function("SayboardKeyboard/KeyboardViewController+Timeout.swift", "func resetProcessingState()")
        self.assertNotIn("settings.isRecording =", body)
        self.assertNotIn("settings.isSessionActive =", body)
        self.assertNotIn("settings.isLLMProcessing =", body)

    def test_manual_ai_starts_bounded_recovery(self):
        body = function("SayboardKeyboard/KeyboardViewController+LLM.swift", "func requestLLMProcessing(", "func requestLLMClipboardProcessing")
        self.assertIn("self.startProcessingTimeout()", body)
        self.assertNotIn("settings.dictationSessionToken =", body)

    def test_busy_ai_has_a_request_scoped_outcome(self):
        body = function("Sayboard/Services/LLMProcessingCoordinator.swift", "private func handleProcessingRequest()", "private func validateRequest")
        self.assertIn("LLMBridge.writeStatus(.busy, requestID: request.requestID)", body)
        self.assertIn("LLMBridge.clearRequest(matching: request.requestID)", body)

    def test_unload_requires_no_capture_or_speech_worker(self):
        body = function("Sayboard/Services/SpeechRecognitionService.swift", "func unloadForLLMProcessing()", "func deactivateCompletely")
        self.assertLess(body.index("guard self.canBeginTextWork"), body.index("await self.unloadAllEngines()"))

    def test_native_speech_worker_is_accounted_until_return(self):
        body = function("Sayboard/Services/SpeechRecognitionService.swift", "func transcribeSamples", "func loadModelIfAvailable")
        self.assertIn("defer { self.speechWorkers -= 1 }", body)
        self.assertIn("self.llmCoordinator?.isProcessing != true", body)

    def test_load_waiter_captures_generation_before_await(self):
        body = function("Sayboard/Services/SenseVoiceTranscriptionService.swift", "if let loadTask {", "guard let folder")
        self.assertLess(body.index("let token = self.generation"), body.index("await loadTask.value"))
        self.assertIn("self.finish(value, generation: token)", body)

    def test_installer_checks_owner_at_promotion(self):
        body = function("Sayboard/Services/BackgroundDownloadManager+Processing.swift", "private func extractToDestination", "private func completeWithSuccess")
        self.assertLess(body.index("guard self.isCurrent(key: key, metadata: metadata)"), body.index("try ModelDownloadInstaller.promote"))
        self.assertIn("defer { self.lock.unlock() }", body)

    def test_old_download_completion_cannot_clear_replacement(self):
        for path, name in [("Sayboard/Services/BackgroundDownloadManager.swift", "func completeWithFailure"),
                           ("Sayboard/Services/BackgroundDownloadManager+Processing.swift", "private func completeWithSuccess")]:
            body = function(path, name)
            self.assertLess(body.index("guard self.isCurrent"), body.index("self.activeMetadata.removeValue"))

    def test_field_epoch_cancels_composition_and_async_candidates(self):
        body = function("SayboardKeyboard/Views/Layouts/AlphabeticKeyboardLayout.swift", ".onChange(of: self.keyboardState.documentEpoch)", ".onChange(of: self.keyboardState.keyboardAppearanceRevision)")
        for code in ("self.clearComposition()", "self.clearShapeComposition()", "self.cantoneseRefreshTask?.cancel()", "self.swipeAlternatives.removeAll()"):
            self.assertIn(code, body)

    def test_conversation_journals_before_opening_audio(self):
        body = function("Sayboard/Services/ConversationCoordinator.swift", "func start(", "func stop(using")
        self.assertLess(body.index("guard self.persistDraft()"), body.index("self.recorder.startRecording("))

    def test_conversation_recovery_uses_shared_sample_budget_before_append(self):
        path = "Sayboard/Services/ConversationCoordinator.swift"
        body = function(path, "private static func readAudio(", "enum ConversationError")
        self.assertIn("ConversationTurnPolicy.canRecoverAudio(", body)
        self.assertIn("sampleRate: file.processingFormat.sampleRate", body)
        self.assertIn("sampleRate: ConversationTurnPolicy.recoverySampleRate", body)
        self.assertIn("samples.reserveCapacity(ConversationTurnPolicy.maximumRecoverySamples)", body)
        self.assertLess(body.index("ConversationTurnPolicy.canAppendRecoverySamples("),
                        body.index("samples.append(contentsOf: chunk)"))
        self.assertNotIn("16_000 * 26", body)
        retry = function(path, "func retry(", "func saveAsMeeting()")
        self.assertIn(".conversation, .failed, operationID: turnID.uuidString", retry)
        self.assertIn(".conversation, .resumed", retry)

    def test_background_download_restore_reconciles_orphans_safely(self):
        manager = source("Sayboard/Services/BackgroundDownloadManager.swift")
        processing = source("Sayboard/Services/BackgroundDownloadManager+Processing.swift")
        models = source("Sayboard/Views/ModelsView.swift")
        app = source("Sayboard/SayboardApp.swift")
        self.assertNotIn("guard !metadataCopy.isEmpty", manager)
        self.assertIn("session.getAllTasks", manager)
        self.assertIn("self.metadataReadBlocked = true", manager)
        self.assertIn("try fm.moveItem(at: fileURL, to: quarantine)", manager)
        self.assertNotIn("try? fm.removeItem(at: fileURL)", manager)
        self.assertIn("self.activeTasks[key] = download", processing)
        self.assertIn("for task in unknownTasks { task.cancel() }", processing)
        self.assertNotIn("DownloadEvent.completed(", processing.split("func processDownloadedFile", 1)[0])
        self.assertIn("self.downloadRecoveryNotice", models)
        self.assertIn("BackgroundDownloadManager.shared.restoreSession()", app)
        self.assertIn("BackgroundDownloadManager.recoveryNoticeKey",
                      source("Sayboard/Services/ModelDownloadService.swift"))
        self.assertIn("BackgroundDownloadManager.recoveryNoticeKey",
                      source("Sayboard/Services/LLMDownloadService.swift"))

    def test_playback_lease_terminal_paths_and_stale_callback(self):
        history = source("Sayboard/Services/AudioPlayerService.swift")
        meeting = source("Sayboard/Services/MeetingAudioPlayback.swift")
        self.assertIn("ObjectIdentifier(player) == completedPlayer", history)
        self.assertIn("BackgroundAudioSession.releasePlayback(owner: self.playbackOwner)", history)
        self.assertIn("if !self.isPlaying { self.stop() }", history)
        self.assertIn("let generation = self.playbackGeneration", meeting)
        self.assertIn("self.playbackGeneration == generation", meeting)
        self.assertIn("BackgroundAudioSession.releasePlayback(owner: self.playbackOwner)", meeting)

    def test_conversation_meeting_transfer_is_idempotent(self):
        conversation = source("Sayboard/Services/ConversationCoordinator.swift")
        meeting = source("Sayboard/Services/MeetingRecordingCoordinator.swift")
        self.assertIn("try FileManager.default.removeItem(at: folder)", conversation)
        self.assertIn("Meeting saved. Conversation draft could not be cleared", conversation)
        self.assertIn("self.records.first(where: { $0.conversationTurns?.map(\\.id) == turnIDs })", meeting)
        self.assertIn("guard saved.conversationTurns == turns else", meeting)
        self.assertIn("struct ConversationTurn: Identifiable, Codable, Sendable, Equatable",
                      source("Shared/ConversationTurn.swift"))

    def test_restore_discovers_orphan_audio_and_normalizes_active_turns(self):
        body = function("Sayboard/Services/ConversationCoordinator.swift", "private func restoreDraft()", "private static func readAudio")
        self.assertIn("self.turns[index].status = .interrupted", body)
        self.assertIn("ConversationTurnPolicy.validAudioFileName", body)
        self.assertIn("decode([ConversationTurn].self", body)

    def test_live_preview_is_scoped_to_visible_current_request(self):
        live = source("SayboardKeyboard/KeyboardViewController+ExperimentalLive.swift")
        for gate in ("self.dictationStartupVisible", "update.sessionToken == self.dictationRequestToken",
                     "update.sessionToken == settings.dictationSessionToken",
                     "update.revision > self.liveTranscriptionRevision"):
            self.assertIn(gate, live)

    def test_meeting_does_not_end_a_borrowed_audio_session(self):
        body = function("Sayboard/Services/MeetingRecordingCoordinator.swift", "func start(", "private func heartbeat()")
        self.assertIn("service.session.captureOwner == nil", body)
        self.assertIn("if sessionStartedHere { try service.session.startSession() }", body)
        self.assertIn("if self.sessionStartedHere { self.speechService?.session.endSession() }", body)

    def test_conversation_prevents_late_turn_or_live_preview_handoff(self):
        body = function("Sayboard/Services/ConversationCoordinator.swift", "private func completeTurn(", "func saveAsMeeting()")
        self.assertGreaterEqual(body.count("self.turns[index].id == turnID"), 3)
        preview = function("Sayboard/Services/ConversationCoordinator.swift", "private func startLivePreview(")
        self.assertIn("self.activeID == sessionID", preview)

    def test_llm_bridge_owns_single_slot_and_replayed_notifications(self):
        bridge = source("Shared/LLMBridge.swift")
        policy = source("Shared/OperationContracts.swift")
        keyboard = source("SayboardKeyboard/KeyboardViewController+LLM.swift")
        self.assertIn("withBridgeLock", bridge)
        self.assertIn("!FileManager.default.fileExists(atPath: url.path)", bridge)
        self.assertIn("phase == .accepted || phase == .running", bridge)
        self.assertIn("!phase.isTerminal { return false }", bridge)
        self.assertIn("case .busy, .rejected: return previous == .requested", policy)
        self.assertNotIn("LLMBridge.clearRequest()", keyboard)
        self.assertNotIn("LLMBridge.clearResult()", keyboard)

    def test_durable_live_insertion_receipt_blocks_reentry_replay(self):
        store = source("Shared/ExperimentalLiveTranscription.swift")
        live = source("SayboardKeyboard/KeyboardViewController+ExperimentalLive.swift")
        controller = source("SayboardKeyboard/KeyboardViewController.swift")
        self.assertIn("O_WRONLY | O_CREAT | O_EXCL", store)
        self.assertIn("hostReceiptPrefix + token + \".receipt\"", store)
        self.assertNotIn("claimHostInsertion(", live)
        self.assertNotIn(".insertText(", live)
        self.assertIn("hasHostInsertionStarted(for: delivery.sessionToken)", controller)
        self.assertIn("failureReason: .awaitingUserInsertion", controller)

    def test_cancelled_live_packets_cannot_resurface(self):
        live = source("SayboardKeyboard/KeyboardViewController+ExperimentalLive.swift")
        self.assertIn("!settings.dictationCancellationRequested", live)
        self.assertIn("update.sessionToken != TranscriptionBridge.cancellationToken()", live)
        cancel = function("SayboardKeyboard/KeyboardViewController.swift",
                          "func cancelDictationViaDarwin()", "func stopDictationViaDarwin()")
        self.assertIn("self.keyboardState.liveSourcePreview = nil", cancel)
        self.assertIn("self.dictationRequestToken = nil", cancel)

    def test_ai_handoff_and_orphan_recovery_use_single_persisted_owner(self):
        controller = source("SayboardKeyboard/KeyboardViewController.swift")
        actions = source("SayboardKeyboard/KeyboardViewController+LLM.swift")
        bridge = source("Shared/LLMBridge.swift")
        toolbar = source("SayboardKeyboard/Views/KeyboardLLMActionsToolbar.swift")
        keyboard = source("SayboardKeyboard/Views/KeyboardView.swift")
        menu = source("SayboardKeyboard/Views/LLMActionBar.swift")
        verifier = source("scripts/verify-llm-bridge.swift")
        delivered = function("SayboardKeyboard/KeyboardViewController.swift",
                            "func insertTranscribedText()", "func pingMainAppForSessionStatus")
        self.assertIn("LLMBridge.ownsDelivery(delivery.resultID)", delivered)
        self.assertIn("sourceDeliveryID: delivery.resultID", delivered)
        after_queue = delivered.split("if self.autoApplyLLMIfNeeded(", 1)[1].split(
            "DiagnosticLog.write(\"keyboard: inserting", 1)[0]
        self.assertNotIn("acknowledgeDelivery", after_queue)
        self.assertIn("var sourceDeliveryID: UUID? = nil", bridge)
        self.assertIn("sourceDeliveryID: request.sourceDeliveryID", bridge)
        self.assertIn("static func recoverableResult()", bridge)
        self.assertIn("self.finishLLMInsertion(acknowledgeSource: true)", actions)
        self.assertIn("func copyRecoverableLLMResult()", actions)
        copy = actions.split("func copyRecoverableLLMResult()", 1)[1].split(
            "func requestLLMClipboardProcessing()", 1)[0]
        self.assertIn("UIPasteboard.general.string = result.text", copy)
        self.assertNotIn("textDocumentProxy.insertText", copy)
        self.assertIn("copyRecoverableLLMResult: () -> Void", keyboard)
        self.assertIn("onRecoverResult:", toolbar)
        self.assertIn("Copy saved text", menu)
        self.assertIn("precondition(LLMBridge.ownsDelivery(deliveryID))", verifier)
        self.assertIn("precondition(LLMBridge.recoverableResult()?.text", verifier)

    def test_llm_destination_change_preserves_original_and_manual_result(self):
        actions = source("SayboardKeyboard/KeyboardViewController+LLM.swift")
        fallback = function("SayboardKeyboard/KeyboardViewController+LLM.swift",
                            "private func insertPendingAutoActionFallback() -> Bool",
                            "private func insertLLMResult()")
        result = function("SayboardKeyboard/KeyboardViewController+LLM.swift",
                          "private func insertLLMResult()",
                          "private func deferLLMResultForManualRecovery()")
        finish = function("SayboardKeyboard/KeyboardViewController+LLM.swift",
                          "private func finishLLMInsertion(", "private func navigateLLMHistory")
        self.assertNotIn("UIPasteboard.general.string =", fallback)
        self.assertIn("guard self.currentLLMFieldMatches()", fallback)
        self.assertIn("return false", fallback)
        self.assertEqual(actions.count("acknowledgeSource: insertedFallback"), 2)
        self.assertIn("self.dictationAutoActionStillFocused(token: self.llmDictationRequestToken)", result)
        self.assertLess(result.index("TranscriptionBridge.acknowledgeDelivery(source)"),
                        result.index("for _ in 0 ..< expected.count"))
        self.assertNotIn("UIPasteboard.general.string = result", result.split(
            "if self.llmClipboardOnly", 1)[1].split(
            "if let originalSelection", 1)[1])
        self.assertIn("if !preserveResultForRecovery", finish)
        self.assertIn("self.refreshRecoverableLLMResult()", finish)
        copy = function("SayboardKeyboard/KeyboardViewController+LLM.swift",
                        "func copyRecoverableLLMResult()", "func requestLLMClipboardProcessing()")
        self.assertLess(copy.index("UIPasteboard.general.string == result.text"),
                        copy.index("LLMBridge.clearResult(matching: result.requestID)"))

    def test_failed_ai_exposes_manual_dictation_without_wrong_field_paste(self):
        actions = source("SayboardKeyboard/KeyboardViewController+LLM.swift")
        menu = source("SayboardKeyboard/Views/LLMActionBar.swift")
        bridge = source("Shared/LLMBridge.swift")
        manual = function("SayboardKeyboard/KeyboardViewController+LLM.swift",
                          "func copyRecoverableLLMResult()", "func requestLLMClipboardProcessing()")
        recovery = function("SayboardKeyboard/KeyboardViewController+LLM.swift",
                            "private func recoverableDictationForManualCopy()",
                            "func copyRecoverableLLMResult()")
        self.assertIn("TranscriptionBridge.readDelivery()", recovery)
        self.assertIn("!LLMBridge.ownsDelivery(delivery.resultID)", recovery)
        self.assertIn("|| self.recoverableDictationForManualCopy() != nil", actions)
        self.assertIn("Copy saved text", menu)
        self.assertIn("UIPasteboard.general.string = delivery.text", manual)
        self.assertLess(manual.index("UIPasteboard.general.string == delivery.text"),
                        manual.index("TranscriptionBridge.acknowledgeDelivery(delivery.resultID)"))
        self.assertNotIn("textDocumentProxy.insertText", manual)
        self.assertIn("guard LLMBridge.clearResult(matching: result.requestID)", manual)
        self.assertIn("static func clearResult(matching requestID: UUID) -> Bool", bridge)

    def test_llm_terminal_status_outlives_keyboard_ack(self):
        bridge = source("Shared/LLMBridge.swift")
        self.assertIn("if self.readStatus(matching: requestID)?.phase.isTerminal == true", bridge)
        self.assertIn("OperationPolicy.mayTransition(", bridge)
        controller = source("SayboardKeyboard/KeyboardViewController+LLM.swift")
        self.assertIn("LLMBridge.writeStatus(.cancelled, requestID: id)", controller)

    def test_cold_fallback_is_scoped_and_development_only(self):
        controller = function("SayboardKeyboard/KeyboardViewController.swift",
                              "private func openDictateDeepLinkFallback", "func cancelDictationViaDarwin")
        self.assertIn("#if APPSTORE", controller)
        self.assertIn("self.keyboardState.dictationOutcome = .sessionRequired", controller)
        self.assertIn("DeepLink.dictateURL(token: token)", controller)
        handler = function("Sayboard/SayboardApp.swift", "case DeepLink.dictateHost:", "case DeepLink.stopHost:")
        self.assertIn("settings.consumeKeyboardRequestIfRecent()", handler)
        self.assertIn("current: settings.dictationSessionToken", handler)
        self.assertIn("TranscriptionBridge.cancellationToken() != token", handler)

    def test_outbox_limits_do_not_delete_unacknowledged_text(self):
        bridge = source("Shared/TranscriptionBridge.swift")
        self.assertIn("guard pending.count < 64", bridge)
        self.assertIn("data.count <= 128 * 1_024", bridge)
        self.assertNotIn("DarwinNotificationName.transcriptionReady", bridge)
        self.assertNotIn("dropFirst(64)", bridge)

    def test_final_delivery_signals_after_host_releases_request(self):
        service = function("Sayboard/Services/SpeechRecognitionService.swift",
                           "private func finishRecording", "func cancelRecording()")
        publish = service.index("TranscriptionBridge.writeTranscription(self.currentTranscription, token: finalizationToken)")
        ready = service.index("DarwinNotificationName.transcriptionReady")
        self.assertLess(service.rindex("self.isCurrentDictation(finalizationToken)", 0, publish), publish)
        self.assertLess(publish, service.rindex("self.settings.dictationSessionToken = nil", 0, ready))
        self.assertLess(service.rindex("self.settings.synchronize()", 0, ready), ready)

    def test_bounded_cross_process_lock_and_result_owner(self):
        bridge = source("Shared/LLMBridge.swift")
        self.assertIn("LOCK_EX | LOCK_NB", bridge)
        self.assertIn("for attempt in 0..<5", bridge)
        self.assertIn("usleep(2_000)", bridge)
        self.assertIn("guard let request = self.readRequest(), request.requestID == requestID", bridge)
        self.assertNotIn("flock(fd, LOCK_EX) == 0", bridge)
        verification = source("scripts/verify-llm-bridge.swift")
        self.assertIn("holder.waitUntilExit()", verification)
        self.assertIn("waited < 0.15", verification)
        self.assertIn("preserved == malformed", verification)

    def test_haptic_disable_does_not_prewarm_engine(self):
        body = function("Shared/KeyboardHaptics.swift", "static func prepare(owner: AnyObject? = nil)")
        self.assertLess(body.index("guard settings.keyboardHapticsEnabled"), body.index("KeyboardCoreHaptic.prewarm"))
        self.assertIn("KeyboardHaptics.suspend(owner: self)", source("SayboardKeyboard/KeyboardViewController.swift"))

    def test_globe_retains_native_selector_and_no_added_gesture(self):
        key = source("SayboardKeyboard/Views/NativeInputModeSwitchKey.swift")
        self.assertNotIn("addGestureRecognizer", key)
        self.assertIn("button.accessibilityLabel", key)
        controller = source("SayboardKeyboard/KeyboardViewController.swift")
        self.assertIn("button.removeTarget(self, action: #selector(handleInputModeList(from:with:))", controller)

    def test_all_data_includes_draft_and_guards_active_operations(self):
        store = source("Sayboard/Services/LocalUserDataStore.swift")
        self.assertIn("case voiceNotes, meetings, vocabulary, conversationDraft", store)
        self.assertIn("guard !self.hasActiveOperation", store)
        self.assertIn('folder.appendingPathComponent("Conversation-Draft"', store)

    def test_load_failure_preserves_verified_files(self):
        body = function("Sayboard/Services/ModelDownloadService+Execution.swift", "    if !loaded {", "  func handleDownloadEvent")
        self.assertNotIn("ModelStorageManager.delete", body)


if __name__ == "__main__":
    unittest.main()
