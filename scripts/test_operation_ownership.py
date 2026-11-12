from pathlib import Path
import unittest

ROOT = Path(__file__).resolve().parent.parent


def source(path):
    return (ROOT / path).read_text()


def function(path, name, next_name=None):
    text = source(path).split(name, 1)[1]
    return text.split(next_name, 1)[0] if next_name else text


class OperationOwnershipTests(unittest.TestCase):
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
        self.assertIn("TranscriptionBridge.readDelivery(matching: vc.dictationRequestToken", observer)
        self.assertNotIn("TranscriptionBridge.readTranscription()", observer)

    def test_completed_dictation_reattaches_to_original_input(self):
        controller = source("SayboardKeyboard/KeyboardViewController.swift")
        policy = source("Shared/DictationRequestPolicy.swift")
        recovery = function("SayboardKeyboard/KeyboardViewController.swift",
                            "private func recoverCompletedDictationDestination()",
                            "func insertTranscribedText()")
        self.assertIn("static func mayRecoverCompleted(", policy)
        self.assertIn("return isSameDestination(", policy)
        self.assertIn("maxAgeSeconds: Self.automaticRecoveryWindow", recovery)
        self.assertIn("DictationRequestPolicy.mayRecoverCompleted(", recovery)
        self.assertIn("fingerprint: settings.dictationDestinationFingerprint", recovery)
        self.assertIn("self.keyboardState.documentEpoch = epoch", recovery)
        self.assertIn("static let automaticRecoveryWindow: TimeInterval = 90", controller)

    def test_146_style_automatic_callbacks_keep_scoped_delivery(self):
        controller = source("SayboardKeyboard/KeyboardViewController.swift")
        insert = function("SayboardKeyboard/KeyboardViewController.swift",
                          "func insertTranscribedText()", "func pingMainAppForSessionStatus")
        self.assertIn("self.recoverCompletedDictationDestination()", insert)
        self.assertIn("self.dictationRequestToken.flatMap { token in", insert)
        self.assertIn("matching: token, allowAnyDestination: true", insert)
        self.assertNotIn("defer { TranscriptionBridge.acknowledgeDelivery", insert)
        self.assertLess(insert.index("delivery.canInsert"), insert.index("TranscriptionBridge.acknowledgeDelivery"))
        self.assertIn("self.insertSpacedText(text)", insert)
        self.assertIn("TranscriptionBridge.acknowledgeDelivery(delivery.resultID)", insert)
        self.assertIn("TranscriptionBridge.cancellationToken() != delivery.sessionToken", controller)
        self.assertNotIn("func insertPendingDictation()", controller)
        self.assertNotIn("refreshPendingDictation()", controller)

    def test_uncertain_live_reconciliation_never_acknowledges(self):
        live = source("SayboardKeyboard/KeyboardViewController+ExperimentalLive.swift")
        controller = source("SayboardKeyboard/KeyboardViewController.swift")
        self.assertIn("enum LiveFinalDeliveryResult", live)
        self.assertIn("case notApplicable, inserted, review", live)
        self.assertIn("return .review", live)
        self.assertIn("return .inserted", live)
        handling = function("SayboardKeyboard/KeyboardViewController.swift",
                            "func insertTranscribedText()", "func pingMainAppForSessionStatus")
        self.assertIn("case .inserted:", handling)
        self.assertIn("case .review:", handling)
        reviewed = handling.split("case .review:", 1)[1].split("case .notApplicable:", 1)[0]
        self.assertNotIn("acknowledgeDelivery", reviewed)
        self.assertNotIn("showFinalOutputPreview(delivery.text)", handling)
        self.assertIn("self.recoverCompletedDictationDestination()", controller)

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

    def test_cancellation_cannot_end_conversation(self):
        body = function("Sayboard/Services/SpeechRecognitionService.swift", "func cancelRecording()", "func transcribeSamples")
        self.assertLess(body.index("ConversationCoordinator.shared.recordingSide == nil"), body.index("self.session.endSession()"))
        self.assertIn("self.cancellationTask == nil", body)
        self.assertIn("await self.awaitExperimentalLiveWorkerExit(cancelledLive)", body)
        self.assertIn("defer { self.cancellationTask = nil }", body)
        self.assertLess(body.index("cancelledLive?.cancel()"), body.index("await self.awaitExperimentalLiveWorkerExit"))

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
        self.assertLess(capture.index("self.speechWorkers == 0"),
                        capture.index("try self.startAudioCapture()"))
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
        self.assertIn("TranscriptionBridge.clearTranscription()", cancel)
        self.assertIn("guard self.isCurrentDictation(requestToken) else { return }", final)
        self.assertIn("guard !Task.isCancelled, self.isRecording else { break }", live)
        self.assertIn("if ExperimentalLiveTranscription.write(", live)

    def test_cancel_wait_is_bounded_and_keeps_native_worker_accounted(self):
        cancel = function("Sayboard/Services/SpeechRecognitionService.swift", "func cancelRecording()", "func transcribeSamples")
        live = function("Sayboard/Services/SpeechRecognitionService+ExperimentalLive.swift", "func awaitExperimentalLiveWorkerExit", "func stopExperimentalLive")
        stop = function("Sayboard/Services/SpeechRecognitionService+ExperimentalLive.swift", "func stopExperimentalLive")
        self.assertIn("for _ in 0..<40", live)
        self.assertLess(live.index("if self.speechWorkers == 0"), live.index("await task?.value"))
        self.assertIn("return false", live)
        self.assertIn("await self.awaitExperimentalLiveWorkerExit(task)", stop)
        self.assertLess(cancel.index("self.cancellationTask == nil"), cancel.index("self.cancellationTask = Task"))
        self.assertIn("if !nativeWorkerExited", cancel)
        self.assertLess(cancel.index("await self.awaitExperimentalLiveWorkerExit(cancelledLive)"), cancel.index("self.isStopping = false"))
        self.assertIn("self.speechWorkers == 0 else", function("Sayboard/Services/SpeechRecognitionService.swift", "func startCapture()", "func scheduleQwenWarmupAfterCapture"))
        self.assertIn("defer { self.speechWorkers -= 1 }", function("Sayboard/Services/SpeechRecognitionService.swift", "func transcribeSamples", "func loadModelIfAvailable"))


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
        self.assertIn('self.openDictateDeepLinkFallback(reason: "cold audio session")', start)
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
        self.assertIn("self.liveTranscriptionBlockedToken = token", restore)
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

    def test_restore_discovers_orphan_audio_and_normalizes_active_turns(self):
        body = function("Sayboard/Services/ConversationCoordinator.swift", "private func restoreDraft()", "private static func readAudio")
        self.assertIn("self.turns[index].status = .interrupted", body)
        self.assertIn("ConversationTurnPolicy.validAudioFileName", body)
        self.assertIn("decode([ConversationTurn].self", body)

    def test_live_session_is_scoped_to_host_field_and_epoch(self):
        live = source("SayboardKeyboard/KeyboardViewController+ExperimentalLive.swift")
        for guard in ("LiveDeliveryPolicy.accepts(", "LiveDeliveryPolicy.matchesField(",
                      "liveTranscriptionOwnerToken", "liveTranscriptionDocumentEpoch",
                      "liveTranscriptionContextAfter"):
            self.assertIn(guard, live)
        controller = source("SayboardKeyboard/KeyboardViewController.swift")
        self.assertIn("if Self.blockedLiveSessionToken != settings.dictationSessionToken", controller)
        self.assertIn("currentDocument == self.dictationDocumentID", controller)
        self.assertIn("DictationRequestPolicy.isSameDestination(", controller)

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

    def test_live_final_plan_and_cancel_tombstone(self):
        live = source("SayboardKeyboard/KeyboardViewController+ExperimentalLive.swift")
        contract = source("Shared/OperationContracts.swift")
        self.assertIn("LiveFinalReconciliation.plan(", live)
        self.assertIn("self.liveTranscriptionOwnerToken ?? self.dictationRequestToken", live)
        for case in ("case .unchanged:", "case .append(let suffix):",
                     "case .replace(let replacement):", "case .review:"):
            self.assertIn(case, live)
        self.assertIn("guard before?.hasSuffix(marked) == true else { return .review }", contract)

    def test_llm_terminal_status_outlives_keyboard_ack(self):
        bridge = source("Shared/LLMBridge.swift")
        self.assertIn("if self.readStatus(matching: requestID)?.phase.isTerminal == true", bridge)
        self.assertIn("OperationPolicy.mayTransition(", bridge)
        controller = source("SayboardKeyboard/KeyboardViewController+LLM.swift")
        self.assertIn("LLMBridge.writeStatus(.cancelled, requestID: id)", controller)

    def test_stale_live_block_is_request_scoped(self):
        controller = source("SayboardKeyboard/KeyboardViewController.swift")
        self.assertIn("self.liveTranscriptionBlockedToken == delivery.sessionToken", controller)
        self.assertIn("Self.blockedLiveSessionToken == delivery.sessionToken", controller)
        self.assertIn("self.abandonExperimentalLiveOwnership()", controller)

    def test_outbox_limits_do_not_delete_unacknowledged_text(self):
        bridge = source("Shared/TranscriptionBridge.swift")
        self.assertIn("guard pending.count < 64", bridge)
        self.assertIn("data.count <= 128 * 1_024", bridge)
        self.assertIn("self.postDarwinNotification(DarwinNotificationName.transcriptionReady)", bridge)
        self.assertNotIn("dropFirst(64)", bridge)

    def test_final_delivery_uses_captured_identity_after_shared_token_clears(self):
        final = function(
            "SayboardKeyboard/KeyboardViewController+ExperimentalLive.swift",
            "func completeExperimentalLiveText(", "func cancelExperimentalLiveText()"
        )
        self.assertIn("LiveFinalDeliveryPolicy.mayReconcile(", final)
        self.assertNotIn("SharedSettings().dictationSessionToken", final)
        self.assertIn("cancelled: cancellationRequested", final)
        self.assertIn("LiveFinalReconciliation.plan(", final)
        insertion = function("SayboardKeyboard/KeyboardViewController.swift",
                             "func insertTranscribedText()", "func pingMainAppForSessionStatus")
        self.assertIn("!settings.dictationCancellationRequested", insertion)
        self.assertIn("delivery, cancellationRequested: settings.dictationCancellationRequested", insertion)
        policy = source("Shared/OperationContracts.swift")
        self.assertIn("delivery.canInsert(requestToken: requestToken", policy)
        self.assertIn("requestDocument == ownedDocument", policy)
        self.assertIn("blockedToken != delivery.sessionToken", policy)

    def test_bounded_cross_process_lock_and_result_owner(self):
        bridge = source("Shared/LLMBridge.swift")
        self.assertIn("LOCK_EX | LOCK_NB", bridge)
        self.assertIn("for attempt in 0..<5", bridge)
        self.assertIn("usleep(2_000)", bridge)
        self.assertIn("self.readRequest()?.requestID == requestID", bridge)
        self.assertNotIn("flock(fd, LOCK_EX) == 0", bridge)
        verification = source("scripts/verify-llm-bridge.swift")
        self.assertIn("holder.waitUntilExit()", verification)
        self.assertIn("waited < 0.15", verification)
        self.assertIn("preserved == malformed", verification)

    def test_haptic_disable_does_not_prewarm_engine(self):
        body = function("Shared/KeyboardHaptics.swift", "static func prepare()")
        self.assertLess(body.index("guard settings.keyboardHapticsEnabled"), body.index("KeyboardCoreHaptic.prewarm"))
        self.assertIn("KeyboardHaptics.suspend()", source("SayboardKeyboard/KeyboardViewController.swift"))

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
