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
