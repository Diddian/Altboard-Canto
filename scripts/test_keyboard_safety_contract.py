"""Regression contracts for keyboard document identity and safe cleanup."""

from pathlib import Path
import unittest

ROOT = Path(__file__).resolve().parent.parent


def source(path: str) -> str:
    return (ROOT / path).read_text(encoding="utf-8")


class KeyboardSafetyContracts(unittest.TestCase):
    def test_cancelled_inference_cannot_deliver_or_finalize_another_request(self):
        speech = source("Sayboard/Services/SpeechRecognitionService.swift")
        pipeline = source("Sayboard/Services/SpeechRecognitionService+Transcription.swift")
        self.assertGreaterEqual(speech.count("guard self.isCurrentDictation(finalizationToken)"), 3)
        decode = pipeline.index("let decodeDurationMs")
        check = pipeline.index("guard self.isCurrentDictation(requestToken)", decode)
        self.assertLess(check, pipeline.index("self.currentRawTranscription = rawText"))
        llm = pipeline.index("await self.llmCoordinator?.processVoiceDictation")
        check = pipeline.index("guard self.isCurrentDictation(requestToken)", llm)
        self.assertLess(check, pipeline.index("TranscriptionBridge.writeTranscription(finalOutput)"))

    def test_meeting_and_dictation_finalization_are_mutually_exclusive(self):
        meeting = source("Sayboard/Services/MeetingRecordingCoordinator.swift")
        speech = source("Sayboard/Services/SpeechRecognitionService.swift")
        self.assertIn("!service.isStopping", meeting)
        self.assertIn("!MeetingRecordingCoordinator.shared.isFinalizing", speech)
        self.assertIn("MeetingRecordingCoordinator.shared.stop(interrupted: true)", speech)

    def test_meeting_rotation_exchanges_writer_without_a_stop_start_gap(self):
        meeting = source("Sayboard/Services/MeetingRecordingCoordinator.swift")
        recorder = source("Sayboard/Services/AudioRecorder.swift")
        heartbeat = meeting.split("private func heartbeat()", 1)[1].split(
            "private func closeCurrentPart()", 1)[0]
        self.assertIn("self.audioRecorder.rotateRecording(", heartbeat)
        self.assertNotIn("self.closeCurrentPart()", heartbeat)
        rotate = recorder.split("func rotateRecording(", 1)[1].split("private func result(", 1)[0]
        self.assertLess(rotate.index("try AVAudioFile("), rotate.index("self.state.withLock"))
        self.assertNotIn("stopRecording()", rotate)
        self.assertIn("snapshot.audioFile.length", recorder)

    def test_failed_manifest_is_not_reported_as_a_saved_meeting(self):
        meeting = source("Sayboard/Services/MeetingRecordingCoordinator.swift")
        self.assertIn("manifestSaved = self.writeManifest(record)", meeting)
        self.assertIn("!manifestSaved ? .failed", meeting)
        self.assertIn("Could not save meeting details; audio files retained", meeting)

    def test_audio_capture_failure_releases_new_session(self):
        audio = source("Sayboard/Services/BackgroundAudioSession.swift")
        speech = source("Sayboard/Services/SpeechRecognitionService.swift")
        self.assertIn("var sessionActivated = false", audio)
        self.assertIn("var tapAttempted = false", audio)
        self.assertIn("if self.audioEngine.isRunning { self.audioEngine.stop() }", audio)
        self.assertIn("if tapAttempted { self.audioEngine.inputNode.removeTap(onBus: 0) }", audio)
        self.assertIn("if sessionActivated {", audio)
        self.assertIn("case audioConversionUnavailable", audio)
        self.assertIn("guard !needsConversion || converter != nil else", audio)
        self.assertIn("func activateTap(accumulator: AudioBufferAccumulator, recorder: AudioRecorder) throws", audio)
        self.assertIn("try self.startAudioCapture()", speech)
        self.assertIn("if sessionStartedHere { self.session.endSession() }", speech)
        self.assertIn("self.settings.lastDictationOutcome = .activationFailed", speech)

    def test_audio_file_failure_is_distinguished_from_success(self):
        recorder = source("Sayboard/Services/AudioRecorder.swift")
        meeting = source("Sayboard/Services/MeetingRecordingCoordinator.swift")
        history = source("Sayboard/Services/SpeechRecognitionService+Transcription.swift")
        self.assertIn("var hasWriteFailure: Bool", recorder)
        self.assertIn("current?.writeFailed = true", recorder)
        self.assertIn("writeFailed: snapshot.writeFailed", recorder)
        self.assertIn("if self.audioRecorder.hasWriteFailure", meeting)
        self.assertIn('record.state = self.incompleteAudio ? .partialAudio', meeting)
        self.assertIn("if result.writeFailed", history)
        self.assertIn("self.currentAudioFileName = nil", history)

    def test_meeting_backlog_is_bounded_without_truncating_saved_audio(self):
        recorder = source("Sayboard/Services/MeetingRecordingCoordinator.swift")
        accumulator = source("Sayboard/Services/AudioBufferAccumulator.swift")
        queue = source("Sayboard/Services/AudioSampleQueue.swift")
        self.assertIn("AudioBufferAccumulator(maximumUnreadSamples: 16_000 * 120)", recorder)
        self.assertIn("self.accumulator.droppedSampleCount", recorder)
        self.assertIn("self.audioRecorder.hasWriteFailure", recorder)
        self.assertIn("private(set) var droppedSamples = 0", queue)
        self.assertIn("var droppedSampleCount: Int", accumulator)
        self.assertIn("active.recorder.appendBuffer(buffer)", source(
            "Sayboard/Services/BackgroundAudioSession.swift"
        ))

    def test_meeting_start_aborts_without_leaking_state(self):
        audio = source("Sayboard/Services/MeetingRecordingCoordinator.swift")
        self.assertIn("let sessionStartedHere = !service.session.isSessionActive", audio)
        self.assertIn("private func abortStart(", audio)
        self.assertIn("if sessionStartedHere { service.session.endSession() }", audio)
        self.assertIn("self.audioRecorder.stopRecording()", audio)
        self.assertIn("if let folder { try? FileManager.default.removeItem(at: folder) }", audio)
        self.assertIn("try service.session.beginCapture(owner: .meeting", audio)
        self.assertIn("self.speechService?.session.endCapture(owner: .meeting)", audio)

    def test_meeting_finalization_processes_bounded_chunks(self):
        meeting = source("Sayboard/Services/MeetingRecordingCoordinator.swift")
        self.assertIn("while self.accumulator.sampleCount > 0", meeting)
        self.assertIn("min(Self.updateSeconds * 16_000, available)", meeting)
        self.assertIn("self.accumulator.consume(count: count)", meeting)
        self.assertNotIn("let remaining = self.accumulator.consumeAll()", meeting)
        self.assertIn('record.state = self.incompleteAudio ? .partialAudio', meeting)
        self.assertIn('interrupted ? .interrupted', meeting)
        self.assertIn(".partialTranscript", meeting)
        self.assertIn('(transcriptIncomplete || self.incompleteAudio) ? .fallback : .completed', meeting)
        queue = source("Sayboard/Services/AudioBufferAccumulator.swift")
        self.assertIn("var sampleCount: Int", queue)
        speech = source("Sayboard/Services/SpeechRecognitionService.swift")
        self.assertIn("let savedSamples = self.accumulator.consumeAll()", speech)

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

    def test_alphabet_has_dedicated_emoji_key_and_native_globe_action(self):
        layout = source("SayboardKeyboard/Views/Layouts/AlphabeticKeyboardLayout.swift")
        chrome = source("SayboardKeyboard/Views/Layouts/KeyboardChrome.swift")
        controller = source("SayboardKeyboard/KeyboardViewController.swift")
        self.assertIn("KeyboardBottomRow(", layout)
        self.assertIn("onEmojiAction: { self.openEmojiPage() }", layout)
        self.assertIn("EmojiKeyboardView(", layout)
        self.assertIn("self.showsEmojiPage = true", layout)
        self.assertIn("self.showsEmojiPage = false", layout)
        self.assertIn("self.keyboardState.needsInputModeSwitchKey", layout)
        self.assertIn("NativeInputModeSwitchKey(", chrome)
        self.assertIn('iconName: "globe"', chrome)
        self.assertIn("if self.keyboardState.showsGlobeButton", chrome)
        self.assertIn("KeyButton(content: .nativeEmojiGlyph", chrome)
        self.assertIn("if let openEmoji = self.onEmojiAction", chrome)
        self.assertIn("keyboardState.effectiveTypingKind == .alphabetic", chrome)
        self.assertIn("else if self.keyboardState.showsGlobeButton", chrome)
        self.assertIn("#selector(handleInputModeList(from:with:))", controller)
        self.assertIn(", keyboardEmoji", source("Shared/FeatureDiagnostics.swift"))

    def test_voice_output_selection_is_checked_before_delivery(self):
        service = source("Sayboard/Services/SpeechRecognitionService.swift")
        pipeline = source("Sayboard/Services/SpeechRecognitionService+Transcription.swift")
        button = source("SayboardKeyboard/Views/TranslateToggleButton.swift")
        self.assertNotIn("recordingOutputOptions", service)
        self.assertNotIn("recordingOutputOptions", pipeline)
        self.assertIn("let options = self.settings.voiceOutputConfiguration", pipeline)
        self.assertGreaterEqual(pipeline.count("VoiceOutputSelectionPolicy.decide("), 2)
        self.assertIn("self.settings.synchronize()", pipeline)
        last_selection = pipeline.rindex("VoiceOutputSelectionPolicy.decide(")
        punctuation = pipeline.index("VoicePunctuationPolicy.render(")
        delivery = pipeline.index("TranscriptionBridge.writeTranscription(finalOutput)")
        self.assertLess(last_selection, punctuation)
        self.assertLess(punctuation, delivery)
        self.assertIn("enabled: options.punctuationEnabled", pipeline)
        self.assertIn("self.targetRawValue = next.target.rawValue", button)
        self.assertIn("FeatureDiagnostics.record(.voiceOutput, .selected)", button)

    def test_resumed_armed_mic_uses_app_owned_live_session(self):
        mic = source("SayboardKeyboard/Views/Layouts/MicAnimatedButton.swift")
        policy = source("Shared/DictationRequestPolicy.swift")
        ping = source("SayboardKeyboard/PingValidator.swift")
        audio = source("Sayboard/Services/BackgroundAudioSession.swift")
        tap = mic.split("private func handleTap()", 1)[1].split(
            "private func handleRecordingChanged", 1
        )[0]
        controller = source("SayboardKeyboard/KeyboardViewController.swift")
        start = controller.split("private func startDictationViaDarwin()", 1)[1].split(
            "private func scheduleWarmStartCheck", 1
        )[0]
        self.assertIn("self.proxy.startDictation()", tap)
        self.assertNotIn("DeepLink.dictateURL", tap)
        self.assertNotIn("settings.dictationSessionToken =", tap)
        self.assertIn("DictationRequestPolicy.shouldRequestWarmSession(", start)
        self.assertIn("appActive: settings.isSessionActive", start)
        self.assertIn("heartbeat: settings.mainAppHeartbeat", start)
        self.assertIn("self.prepareDictationDestination()", start)
        self.assertIn('self.openDictateDeepLinkFallback(reason: "cold audio session")', start)
        self.assertLess(start.index("TranscriptionBridge.postDarwinNotification("),
                        start.index('self.openDictateDeepLinkFallback(reason: "cold audio session")'))
        self.assertIn("hasRecentAudioHeartbeat", policy)
        self.assertIn("lastHeartbeat.withLock", audio)
        self.assertNotIn("settings.isSessionActive = false", ping)
        self.assertNotIn("settings.isRecording = false", ping)
        self.assertIn("keyboardState.isRecording = false", ping)
        self.assertLess(ping.index("DictationRequestPolicy.hasRecentAudioHeartbeat("),
                        ping.index("keyboardState.isRecording = false"))

    def test_armed_mic_fallback_is_token_scoped_and_cancels_on_hide(self):
        controller = source("SayboardKeyboard/KeyboardViewController.swift")
        policy = source("Shared/DictationRequestPolicy.swift")
        start = controller.split("private func startDictationViaDarwin()", 1)[1].split(
            "private func openDictateDeepLinkFallback", 1
        )[0]
        disappearance = controller.split("override func viewWillDisappear", 1)[1].split(
            "override func didReceiveMemoryWarning", 1
        )[0]
        self.assertIn("let token = UUID().uuidString", start)
        self.assertIn("DictationRequestPolicy.isCurrent(", start)
        self.assertIn("DictationRequestPolicy.shouldOpenColdFallback(", start)
        self.assertIn("self.viewIfLoaded?.window != nil", start)
        self.assertIn("audioAlive && retryCount == 0", start)
        self.assertIn("self.scheduleWarmStartCheck(token: token, retryCount: 1)", start)
        self.assertIn("self.warmStartSessionAcknowledged", start)
        self.assertIn("self.staleFallbackTimer?.invalidate()", disappearance)
        self.assertIn("self.pingValidator.cancel()", disappearance)
        self.assertNotIn("settings.isSessionActive = false", controller)
        self.assertIn("&& keyboardVisible && !recording && !appAcknowledged", policy)
        self.assertIn("settings.dictationCancellationRequested = true", controller)
        self.assertIn("vc.warmStartSessionAcknowledged = true", controller)

    def test_touch_state_does_not_outlive_keyboard(self):
        controller = source("SayboardKeyboard/KeyboardViewController.swift")
        delete = source("SayboardKeyboard/Views/RepeatDeleteButton.swift")
        self.assertIn("lastTouchDocumentID", controller)
        self.assertIn("KeyboardTouchLearning.shared.invalidate()", controller)
        self.assertIn("self.pressed = false", delete)
        self.assertIn("KeyboardTouchLearning.shared.invalidate()", delete)


if __name__ == "__main__":
    unittest.main()


