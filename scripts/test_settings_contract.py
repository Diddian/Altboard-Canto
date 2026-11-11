#!/usr/bin/env python3
"""Source-level contracts for user-facing settings and keyboard flows."""
from pathlib import Path
import unittest

ROOT = Path(__file__).resolve().parent.parent


def read(path):
    return (ROOT / path).read_text(encoding="utf-8")


class SettingsContractTests(unittest.TestCase):
    def test_language_priority_uses_native_form_row_geometry(self):
        source = read("Sayboard/Views/SpeechLanguagesSettingsView.swift")
        selection = source.split("private var languageSelectionRows", 1)[1].split(
            "private var languagePrioritySummary", 1
        )[0]
        self.assertIn('Text("Language Priority")', selection)
        self.assertIn('Label {', selection)
        self.assertNotIn(".frame(height: 31)", selection)
        self.assertNotIn('.frame(width: 24)', selection)

    def test_opt_in_spelling_and_native_key_clicks(self):
        settings = read("Sayboard/Views/KeyboardSettingsView.swift")
        shared = read("Shared/SharedSettings.swift")
        controller = read("SayboardKeyboard/KeyboardViewController.swift")
        haptics = read("Shared/KeyboardHaptics.swift")
        latin = read("SayboardKeyboard/LatinWordSuggestions.swift")
        layout = read("SayboardKeyboard/Views/Layouts/AlphabeticKeyboardLayout.swift")
        self.assertIn('Toggle("Auto-Correction", isOn: self.$autoCorrectionEnabled)', settings)
        self.assertIn('Toggle("Spell Check", isOn: self.$spellCheckingEnabled)', settings)
        self.assertIn('private var autoCorrectionEnabled = false', settings)
        self.assertIn('private var spellCheckingEnabled = false', settings)
        self.assertIn('var keyboardAutoCorrectionEnabled: Bool', shared)
        self.assertIn('var keyboardSpellCheckingEnabled: Bool', shared)
        self.assertIn('extension UIInputView: @retroactive UIInputViewAudioFeedback', controller)
        self.assertIn('enableInputClicksWhenVisible: Bool { true }', controller)
        self.assertNotIn('self.inputView =', controller)
        self.assertIn('UIDevice.current.playInputClick()', haptics)
        self.assertIn('spellCheckEnabled && typed.count >= 3', latin)
        self.assertIn('func automaticCorrection(for typed:', latin)
        self.assertIn('self.autoCorrectionEnabled && self.page == .letters', layout)
        self.assertIn('self.composition.isEmpty || self.isLatinGrid', layout)
        self.assertIn('LatinWordSuggestionPolicy.canReplace(typed, in: context)', layout)

    def test_one_pass_conversation_translation_uses_voice_output(self):
        source = read("Sayboard/Services/LLMProcessingCoordinator.swift")
        body = source.split('func processConversationTurn(', 1)[1].split(
            'private func processVoiceChunks(', 1
        )[0]
        self.assertIn('if options.target != .original', body)
        self.assertIn('onCleaned(source)', body)
        self.assertIn('let translation = await self.processVoiceChunks(source, options: options)', body)
        self.assertNotIn('cleanupOptions', body)
        self.assertIn('guard !Task.isCancelled', body)
        self.assertIn('Correct clear ASR and source grammar mistakes',
                      read("Shared/VoiceOutputOptions.swift"))

    def test_keyboard_option_toggle_and_preview_share_one_state_owner(self):
        parent = read("Sayboard/Views/KeyboardSettingsView.swift")
        editor = read("Sayboard/Views/KeyboardCustomizationView.swift")
        self.assertIn('showGlobe: self.$showExtraGlobeKey', parent)
        self.assertIn('showSettingsKey: self.$showSettingsKey', parent)
        self.assertIn('showOutputButton: self.$showOutputLanguageButton', parent)
        self.assertIn('showAIButton: self.$showAIButton', parent)
        for property_name in ('showExtraGlobeKey', 'showSettingsKey',
                              'showOutputLanguageButton', 'showAIButton'):
            self.assertIn(f'{property_name}: self.{property_name}', parent)
        self.assertEqual(parent.count("@AppStorage(SharedKey.keyboardShowGlobeKey"), 1)
        self.assertIn("@Binding var showGlobe: Bool", editor)
        self.assertNotIn("@AppStorage(SharedKey.keyboardShowGlobeKey", editor)
        self.assertIn('if self.systemSwitchRequired && !self.showExtraGlobeKey', parent)

    def test_conversation_symmetric_controls_and_live_prewarm(self):
        view = read("Sayboard/Views/ConversationView.swift")
        owner = read("Sayboard/Services/ConversationCoordinator.swift")
        speech = read("Sayboard/Services/SpeechRecognitionService.swift")
        events = read("Shared/FeatureDiagnostics.swift")
        policy = read("Shared/LiveDictationChunkPolicy.swift")
        self.assertIn('.toolbar(.hidden, for: .navigationBar)', view)
        self.assertIn('.overlay(alignment: .bottomTrailing)', view)
        self.assertIn('self.conversationOptions', view)
        self.assertNotIn('ToolbarItem(placement: .topBarTrailing)', view)
        self.assertIn('if target != .original', view)
        self.assertIn('self.conversation.prepareLivePreview(using: self.speechService)', view)
        self.assertIn('func prepareLivePreview(using service: SpeechRecognitionService)', owner)
        self.assertIn('self.warmupTask == nil', owner)
        self.assertIn('service.activeLoadState == .unloaded', owner)
        self.assertIn('if self.recordingSide != nil { self.startLivePreview(using: service) }', owner)
        self.assertIn('await self.warmupTask?.value', owner)
        self.assertIn('guard self.liveTask == nil', owner)
        self.assertIn('case .noSpeech:', owner)
        self.assertIn('static let firstQwenSamples = 24_000', policy)
        self.assertIn('failureReason: .insufficientMemory', owner)
        self.assertIn('failureReason: .insufficientMemory', speech)
        self.assertIn('insufficientMemory', events)
        self.assertNotIn('URLSession', owner + view)

    def test_unpreferred_qwen_headers_are_cleaned_at_shared_ingress(self):
        sanitizer = read("Shared/TextSanitizer.swift")
        tests = read("SayboardTests/TextSanitizerTests.swift")
        final = read("Sayboard/Services/SpeechRecognitionService+Transcription.swift")
        live = read("Sayboard/Services/SpeechRecognitionService+ExperimentalLive.swift")
        conversation = read("Sayboard/Services/ConversationCoordinator.swift")
        self.assertIn('qwenLanguageHeaderPattern', sanitizer)
        self.assertIn('ASR[ \\t_]+text', sanitizer)
        self.assertNotIn('(?:Cantonese|English|German|Chinese|Mandarin|Yue)', sanitizer)
        self.assertIn('language French<asr_text>Bonjour', tests)
        self.assertIn('language Japanese → ASR text →', tests)
        self.assertIn('qwen3DoesNotEraseRealSpokenWords', tests)
        for owner in (final, live, conversation):
            self.assertIn('TextSanitizer.sanitize(', owner)

    def test_one_microphone_owner_for_dictation_and_meetings(self):
        audio = read("Sayboard/Services/BackgroundAudioSession.swift")
        speech = read("Sayboard/Services/SpeechRecognitionService.swift")
        meeting = read("Sayboard/Services/MeetingRecordingCoordinator.swift")
        self.assertIn("enum UnifiedCaptureOwner: String, Sendable", audio)
        self.assertIn("case dictation, meeting, conversation", audio)
        self.assertIn("guard self.captureOwner == nil else", audio)
        self.assertIn("throw AudioSessionError.alreadyCapturing", audio)
        self.assertIn("guard self.captureOwner == owner else { return }", audio)
        self.assertIn("self.captureOwner = nil", audio)
        self.assertIn("self.session.beginCapture(owner: .dictation", speech)
        self.assertIn("self.session.endCapture(owner: .dictation)", speech)
        self.assertIn("service.session.beginCapture(owner: .meeting", meeting)
        self.assertIn("self.speechService?.session.endCapture(owner: .meeting)", meeting)
        self.assertIn("self.deactivateTap()", audio.split("func endSession()", 1)[1])
        self.assertEqual(audio.count("inputNode.installTap(onBus: 0"), 1)

    def test_meeting_and_dictation_share_one_asr_dispatch(self):
        speech = read("Sayboard/Services/SpeechRecognitionService.swift")
        output = read("Sayboard/Services/SpeechRecognitionService+Transcription.swift")
        meeting = read("Sayboard/Services/MeetingRecordingCoordinator.swift")
        self.assertIn("func transcribeSamples(_ samples: [Float]) async -> TranscriptionResult", speech)
        self.assertIn("case .senseVoice:", speech)
        self.assertIn("self.senseVoiceService.transcribe(audioSamples: samples)", speech)
        self.assertIn("await self.transcribeSamples(samples)", output)
        self.assertIn("await service.transcribeSamples(samples)", meeting)
        self.assertNotIn("service.qwen3Service.transcribe(", meeting)
        self.assertNotIn("selectedVariant == .qwen3ASR17B", meeting)

    def test_multilingual_model_download_and_experiment_are_bounded(self):
        catalog = read("Shared/ModelVariant.swift")
        models = read("Sayboard/Views/ModelsView.swift")
        download = read("Sayboard/Services/SenseVoiceModelDownloader.swift")
        installed = read("Sayboard/Services/SenseVoiceModelBundle.swift")
        source = read("Sayboard/Services/ModelDownloadService+Execution.swift")
        self.assertIn('case senseVoiceSmall = "sensevoice-small-yue-int8-2025-09"', catalog)
        self.assertIn('["yue", "zh", "en", "ja", "ko"]', catalog)
        self.assertIn('["tr", "ar", "ja"]', read("SayboardTests/ModelVariantCapabilityTests.swift"))
        for label in ("Türkçe", "日本語", "العربية"):
            self.assertIn(label, models)
        self.assertIn("try await SenseVoiceModelDownloader.download", source)
        self.assertIn("computeSHA256(of: model)", download)
        self.assertIn("try Task.checkCancellation()", download)
        self.assertIn('modelSHA256 =', installed)
        self.assertIn("isDownloaded(variant)", read("Sayboard/Services/ModelDownloadService.swift"))
        self.assertIn("!MeetingRecordingCoordinator.shared.isRecording", read("Sayboard/Services/ModelDownloadService.swift"))
        self.assertIn("guard self.modelLoader?.isModelInUse != true", read("Sayboard/Services/ModelDownloadService.swift"))
        self.assertIn("Accuracy: Unrated", read("Sayboard/Views/ModelCardView.swift"))
        self.assertIn("Speed: Unrated", read("Sayboard/Views/ModelCardView.swift"))

    def test_stop_live_decode_bounded_and_audio_preserved_after_native_stall(self):
        live = read("Sayboard/Services/SpeechRecognitionService+ExperimentalLive.swift")
        service = read("Sayboard/Services/SpeechRecognitionService.swift")
        final = read("Sayboard/Services/SpeechRecognitionService+Transcription.swift")
        self.assertIn("func stopExperimentalLive() async -> Bool", live)
        self.assertIn("for _ in 0..<40", live)
        self.assertIn("if self.speechWorkers == 0", live)
        self.assertIn("Native ASR worker did not stop; audio retained", live)
        self.assertIn("let liveStopped = await self.stopExperimentalLive()", service)
        self.assertIn("if !liveStopped && self.speechWorkers > 0", service)
        self.assertIn("saveHistoryRecord(preserveUntranscribedAudio: true)", service)
        self.assertIn("Recognition interrupted — audio preserved for playback", final)
        self.assertIn("func saveHistoryRecord(preserveUntranscribedAudio: Bool = false)", final)
        self.assertIn('TranscriptionBridge.postDarwinNotification(DarwinNotificationName.dictationStopped)', service)

    def test_visible_keyboard_recovers_cancel_and_animation_without_spinning_state(self):
        timeout = read("SayboardKeyboard/KeyboardViewController+Timeout.swift")
        host = read("SayboardKeyboard/KeyboardViewController.swift")
        mic = read("SayboardKeyboard/Views/Layouts/MicAnimatedButton.swift")
        self.assertIn("func resumeProcessingTimeoutIfNeeded()", timeout)
        self.assertIn("Date(timeIntervalSinceReferenceDate: progress.startedAt)", timeout)
        self.assertGreaterEqual(host.count("self.resumeProcessingTimeoutIfNeeded()"), 2)
        self.assertIn("self.cancelDictationViaDarwin()", timeout)
        self.assertIn('Cancel dictation processing', mic)
        self.assertIn("if self.keyboardState.isProcessing {", mic)
        self.assertIn("self.proxy.cancelDictation()", mic)
        self.assertNotIn(".allowsHitTesting(!self.keyboardState.isProcessing)", mic)
        self.assertIn("TwoDotOrbitProcessing(size: self.sizing.spinnerSize)", mic)
        self.assertIn("accessibilityReduceMotion", mic)
        self.assertIn("TimelineView(.animation(minimumInterval:", mic)

    def test_live_first_word_latency_and_retry_without_dropping_audio(self):
        policy = read("Shared/LiveDictationChunkPolicy.swift")
        shared = read("Shared/ExperimentalLiveTranscription.swift")
        speech = read("Sayboard/Services/SpeechRecognitionService+ExperimentalLive.swift")
        keyboard = read("SayboardKeyboard/KeyboardViewController+ExperimentalLive.swift")
        host = read("SayboardKeyboard/KeyboardViewController.swift")
        diagnostics = read("Sayboard/Views/DiagnosticsView.swift")
        self.assertIn("static let firstQwenSamples = 24_000", policy)
        self.assertIn("static let firstWindowOptions = [3_200, 8_000, 16_000, 24_000]", policy)
        self.assertIn("static func retryFirstWindow(after samples: Int)", policy)
        self.assertIn("let firstWindow = self.settings.liveFirstWindowSamples", speech.replace("var firstWindow", "let firstWindow")) 
        self.assertIn("if firstChunk && !published", speech)
        self.assertIn("firstWindow = next", speech)
        self.assertIn("readOffset += samples.count", speech)
        self.assertIn("LiveDictationLatency.mark(.firstHostInsert", keyboard)
        self.assertIn("LiveDictationLatency.begin(token: token)", host)
        self.assertIn("enum LiveDictationLatency", shared)
        self.assertIn("Never persist recognized or host text", shared)
        self.assertIn("Mic → first text in host", diagnostics)
        self.assertIn('Text("0.2 s (experimental)")', diagnostics)
        self.assertIn("liveDictationLatencyMs", read("Shared/FeatureDiagnostics.swift"))

    def test_live_original_is_visible_before_final_translation(self):
        extension = read("SayboardKeyboard/KeyboardViewController+ExperimentalLive.swift")
        keyboard = read("SayboardKeyboard/KeyboardState.swift")
        chrome = read("SayboardKeyboard/Views/Layouts/KeyboardChrome.swift")
        speech = read("Sayboard/Services/SpeechRecognitionService+ExperimentalLive.swift")
        self.assertNotIn("guard settings.voiceOutputTarget == .original else { return }", extension)
        self.assertIn("liveSourcePreview = String(update.text.suffix(240))", extension)
        self.assertIn("func completeExperimentalLiveText(_ final: String) -> Bool", extension)
        self.assertIn("guard owned == self.availableDocumentIdentifier()", extension)
        self.assertIn('Text("Live Transcription")', chrome)
        self.assertIn("self.keyboardState.liveSourcePreview", chrome)
        self.assertIn("self.liveSourcePreview = nil", keyboard)
        self.assertIn("if ExperimentalLiveTranscription.write(", speech)
        self.assertIn("sessionToken: token, revision: revision + 1", speech)
        status_strip = chrome.split("struct KeyboardStatusStrip: View", 1)[1].split("struct KeyboardBottomRow: View", 1)[0]
        self.assertNotIn("proxy.insertText(", status_strip)

    def test_history_correction_is_english_and_keyboard_safe(self):
        row = read("Sayboard/Views/HistoryRowView.swift")
        history = read("Sayboard/Views/HistoryListView.swift")
        self.assertNotIn('Text("ASR 原文")', row)
        self.assertNotIn('Text("你真正講過嘅內容")', row)
        self.assertIn('Text("Original Language")', row)
        self.assertIn("private var correctionEditor: some View", row)
        self.assertIn("TextEditor(text: self.$correctedDraft)", row)
        self.assertIn('Button("Cancel")', row)
        self.assertIn('Button("Save & Learn")', row)
        self.assertNotIn('.sheet(isPresented: self.$isEditing)', row)
        self.assertIn("self.correctionFocused = false", row)
        self.assertIn("self.isEditing = false", row)
        self.assertIn("self.keyboardTestingText = \"\"", history)
        self.assertIn("self.isKeyboardTestFocused = false", history)

    def test_conversation_reuses_audio_capture_asr_translation_and_meeting(self):
        coordinator = read("Sayboard/Services/ConversationCoordinator.swift")
        meeting = read("Sayboard/Services/MeetingRecordingCoordinator.swift")
        shared = read("Shared/ConversationTurn.swift")
        tab = read("Sayboard/Views/MainTabView.swift")
        ui = read("Sayboard/Views/ConversationView.swift")
        diagnostics = read("Shared/FeatureDiagnostics.swift")
        for snippet in (
            "service.session.beginCapture(",
            "owner: .conversation",
            "service.session.endCapture(owner: .conversation)",
            "await service.transcribeSamples(samples)",
            "await coordinator.processConversationTurn(",
            "self.persistDraft()",
            "self.restoreDraft()",
            "func retry(",
            "func saveAsMeeting() -> Bool",
            "MeetingRecordingCoordinator.shared.saveConversation(",
            "VoiceOutputConfiguration",
            "os_proc_available_memory()",
        ):
            self.assertIn(snippet, coordinator)
        self.assertIn("func saveConversation(", meeting)
        self.assertIn("record.conversationTurns = turns", meeting)
        self.assertIn("ConversationTurnPolicy.validAudioFileName", meeting)
        self.assertIn("var conversationTurns: [ConversationTurn]? = nil", meeting)
        self.assertIn("static func validOutput(", shared)
        self.assertIn("case meeting, meetingTranslation, conversation,", diagnostics)
        self.assertEqual(tab.count('ConversationView()'), 2)
        self.assertIn('Tab("Conversation", systemImage:', tab)
        self.assertIn("case conversation", tab)
        self.assertIn("rotationEffect(.degrees(180))", ui)
        self.assertIn("let recent = self.conversation.turns.last", ui)
        self.assertIn("speakerOwnsLastTurn || recent?.targetCode == \"\"", ui)
        self.assertIn("self.targetPicker(side: side)", ui)
        self.assertIn("self.visibleSource(self.conversation.liveSource, spokenBy: activeSpeaker ?? side)", ui)
        self.assertIn("if target != .original", ui)
        self.assertIn("let target = speaker == .me ? self.visitorOutput : self.myOutput", ui)
        self.assertIn('Text(self.localeText(live ? "live"', ui)
        self.assertIn('Live-Transkription', ui)
        self.assertIn('即時語音轉文字', ui)
        self.assertIn('Image(systemName: "arrow.left.arrow.right")', ui)
        self.assertIn("self.conversation.saveAsMeeting()", ui)
        self.assertIn("ConversationTurnPolicy.validOutput", ui)
        self.assertNotIn("URLSession", coordinator + meeting + ui)

    def test_live_and_meeting_transcripts_keep_source_script(self):
        meeting = read("Sayboard/Services/MeetingRecordingCoordinator.swift")
        live = read("Sayboard/Services/SpeechRecognitionService+ExperimentalLive.swift")
        conversation = read("Sayboard/Services/ConversationCoordinator.swift")
        ui = read("Sayboard/Views/ConversationView.swift")
        self.assertIn("let clean = TextSanitizer.sanitize(raw)", meeting)
        self.assertIn("let cleaned = CantoneseOutput.normalizeDictation(", live)
        self.assertIn("preferredLanguages: self.recordingSpokenLanguages", live)
        self.assertIn("LiveDictationChunkPolicy.samples(", conversation)
        self.assertIn("hasAttemptedFirst: hasAttemptedFirst", conversation)
        self.assertIn("spokenBy: activeSpeaker ?? side", ui)
        self.assertIn("selected == .cantonese ? CantoneseOutput.normalize(source) : source", ui)

    def test_meeting_translation_failure_has_recovery_and_saved_output(self):
        meeting = read("Sayboard/Services/MeetingRecordingCoordinator.swift")
        view = read("Sayboard/Views/MeetingRecordsView.swift")
        inference = read("Sayboard/Services/LLMProcessingCoordinator.swift")
        self.assertIn("translationStatusRecordID = id", meeting)
        self.assertIn("coordinator.lastVoiceOutputIssue", meeting)
        self.assertIn("let displayed = CantoneseOutput.normalizeForOutput(translated, options: options)", inference)
        self.assertIn('ShareLink("Share Translation", item: translated)', view)
        self.assertIn("translationDraftText", view)
        self.assertNotIn("No translation saved yet.", view)

    def test_conversation_beta_status_uses_native_badge_on_both_tab_modes(self):
        tabs = read("Sayboard/Views/MainTabView.swift")
        screen = read("Sayboard/Views/ConversationView.swift")
        self.assertEqual(tabs.count('.badge("Beta")'), 2)
        liquid = tabs.split('Tab("Conversation", systemImage:', 1)[1].split(
            'Tab("Meetings", systemImage:', 1
        )[0]
        legacy = tabs.split('Label("Conversation", systemImage:', 1)[1].split(
            'Label("Meetings", systemImage:', 1
        )[0]
        self.assertIn('.badge("Beta")', liquid)
        self.assertIn('.badge("Beta")', legacy)
        self.assertIn('ConversationView()', liquid)
        # Legacy's NavigationStack comes before its tabItem label.
        legacy_stack = tabs.split('private var legacyTabs: some View', 1)[1].split(
            'NavigationStack(path: self.$meetingsPath)', 1
        )[0]
        self.assertIn('ConversationView()', legacy_stack)
        self.assertNotIn('.navigationTitle("Conversation")', screen)
        self.assertIn('.toolbar(.hidden, for: .navigationBar)', screen)

    def test_conversation_output_languages_do_not_change_globals(self):
        view = read("Sayboard/Views/ConversationView.swift")
        coordinator = read("Sayboard/Services/ConversationCoordinator.swift")
        meeting = read("Sayboard/Services/MeetingRecordingCoordinator.swift")
        self.assertIn("self.captureOptions = options", coordinator)
        self.assertIn("self.captureOptions ?? Self.defaultOutput(for: side)", coordinator)
        self.assertIn("ConversationTurnPolicy.validOutput(", coordinator)
        self.assertIn("let options = selectedOptions ?? settings.voiceOutputConfiguration", meeting)
        self.assertIn("target: self.selectedTarget", view if "target: self.selectedTarget" in view else read("Sayboard/Views/MeetingRecordsView.swift"))
        self.assertNotIn("settings.voiceOutputTarget =", coordinator + view)

    def test_unpreferred_languages_are_not_dropped_before_translation(self):
        source = read("Sayboard/Services/SpeechRecognitionService+Transcription.swift")
        whisper = read("Sayboard/Services/WhisperKitTranscriptionService.swift")
        self.assertIn("FeatureDiagnostics.record(.language, .fallback)", source)
        self.assertIn("source retained for output processing", source)
        self.assertNotIn("self.settings.lastDictationOutcome = .unexpectedLanguage", source)
        self.assertIn("detectLanguage: true", whisper)
        self.assertIn("language: nil", whisper)
        self.assertNotIn("lockedLanguage", whisper)
        keyboard = read("SayboardKeyboard/KeyboardViewController+ExperimentalLive.swift")
        self.assertNotIn("guard settings.voiceOutputTarget == .original else { return }", keyboard)

    def test_meeting_translation_continues_after_navigation(self):
        view = read("Sayboard/Views/MeetingRecordsView.swift")
        coordinator = read("Sayboard/Services/MeetingRecordingCoordinator.swift")
        self.assertNotIn(".onDisappear { self.recorder.cancelTranslation", view)
        self.assertIn("Button(\"Pause Translation\")", view)
        self.assertIn("self.recorder.cancelTranslation(id: self.record.id)", view)
        self.assertIn("translationTask?.cancel()", coordinator)

    def test_multilingual_generation_is_bounded_and_utf8_safe(self):
        inference = read("Sayboard/Services/LLMInferenceService.swift")
        coordinator = read("Sayboard/Services/LLMProcessingCoordinator.swift")
        self.assertIn("var outputBytes = [UInt8]()", inference)
        self.assertIn("outputBytes.append(contentsOf: piece)", inference)
        self.assertIn("String(decoding: outputBytes, as: UTF8.self)", inference)
        piece_body = inference.split("private nonisolated static func piece(", 1)[1].split("private nonisolated static func makeSampler", 1)[0]
        self.assertNotIn("String(bytes: bytes, encoding: .utf8)", piece_body)
        self.assertIn("return bytes", piece_body)
        self.assertIn("maxOutputTokens: min(512, max(192, input.utf8.count * 2))", coordinator)
        self.assertIn("Task.isCancelled ? .cancelled : .failed", coordinator)

    def test_saved_meeting_translation_is_separate_and_resumable(self):
        coordinator = read("Sayboard/Services/MeetingRecordingCoordinator.swift")
        view = read("Sayboard/Views/MeetingRecordsView.swift")
        shared = read("Shared/MeetingTranslationPolicy.swift")
        self.assertIn("var translatedTranscript: String? = nil", coordinator)
        self.assertIn("var translationDraftNextChunk: Int? = nil", coordinator)
        self.assertIn("func translateRecord(", coordinator)
        self.assertIn("options selectedOptions: VoiceOutputConfiguration? = nil", coordinator)
        self.assertIn("MeetingTranslationPolicy.sourceFingerprint(", coordinator)
        self.assertIn("MeetingTranslationPolicy.canResume(", coordinator)
        self.assertIn("self.writeManifest(updated, includeTranscript: false)", coordinator)
        self.assertIn("self.records[position] = updated", coordinator)
        self.assertIn("finished.translatedTranscript = finished.translationDraftText", coordinator)
        self.assertIn("SharedSettings().voiceOutputTarget != .original", coordinator)
        self.assertIn("self.translateRecord(id: saved.id, using: service)", coordinator)
        self.assertIn("self.translatingRecordID != id", coordinator)
        self.assertIn("self.translatingRecordID == nil", coordinator)
        self.assertIn("let record = try? JSONDecoder().decode(MeetingRecord.self, from: data)", coordinator)
        self.assertIn('Section("Translation")', view)
        self.assertIn('ShareLink("Share Translation", item: translated)', view)
        self.assertIn("translationStatusRecordID == self.record.id", view)
        self.assertIn("lastVoiceOutputIssue", read("Sayboard/Services/MeetingRecordingCoordinator.swift"))
        self.assertIn("self.recorder.translateRecord(", view)
        self.assertIn("options: self.translationOptions", view)
        self.assertIn('Picker("Translate to", selection: self.$meetingTarget)', view)
        self.assertNotIn("Select an output language in Settings to translate this saved recording.", view)
        self.assertIn("self.recorder.cancelTranslation(id: self.record.id)", view)
        self.assertIn("self.recorder.cancelTranslation(id: self.record.id)", view)
        self.assertIn("static let maximumChunkCharacters = 180", shared)
        self.assertNotIn("FeatureDiagnostics.record(.meetingTranslation, .completed,", coordinator)

    def test_translation_model_owner_and_cancellation_are_not_duplicated(self):
        coordinator = read("Sayboard/Services/LLMProcessingCoordinator.swift")
        inference = read("Sayboard/Services/LLMInferenceService.swift")
        pipeline = read("Sayboard/Services/SpeechRecognitionService+Transcription.swift")
        diagnostics = read("Shared/FeatureDiagnostics.swift")
        self.assertIn("func translateMeetingChunks(", coordinator)
        self.assertIn("await self.processVoiceChunk(chunks[current], options: options)", coordinator)
        self.assertIn("VoiceOutputPrompt.compactPrompt(for: options)", coordinator)
        self.assertIn("static func compactPrompt(for options: VoiceOutputConfiguration)", read("Shared/VoiceOutputOptions.swift"))
        self.assertIn("MeetingTranslationPolicy.chunks(input)", coordinator)
        self.assertIn("let displayed = CantoneseOutput.normalizeForOutput(translated, options: options)", coordinator)
        self.assertIn("onTranslated(current + 1, displayed)", coordinator)
        self.assertIn("self.endVoiceProcessing(backgroundTask)", coordinator)
        self.assertIn("return await self.inferenceService.process(", coordinator)
        self.assertNotIn("withTaskGroup(of: String?.self)", coordinator)
        self.assertIn("let worker = Task.detached(priority: .userInitiated)", inference)
        self.assertIn("await worker.value", inference)
        self.assertIn("worker.cancel()", inference)
        self.assertIn("case meeting, meetingTranslation, conversation,", diagnostics)
        self.assertIn("options.needsLLM && !modelOutputMissing", pipeline)
        self.assertIn("FeatureDiagnostics.record(.voiceOutput, .fallback)", pipeline)

    def test_cantonese_output_rejects_nonhan_fallback(self):
        output = read("Shared/VoiceOutputOptions.swift")
        validator = output.split("enum VoiceLanguageValidator", 1)[1]
        self.assertIn("guard !foreignScript else { return false }", validator)
        self.assertNotIn("han > 0 || latin < 8", validator)
        self.assertIn("CharacterSet.decimalDigits.contains($0)", validator)

    def test_language_priority_is_one_row_with_existing_editor(self):
        source = read("Sayboard/Views/SpeechLanguagesSettingsView.swift")
        self.assertIn('self.showPreferredLanguagePicker = true', source)
        self.assertIn('Text(verbatim: self.languagePrioritySummary)', source)
        self.assertIn('codes.first.map { PreferredVoiceLanguages.shortLabel(for: $0) } ?? "AUTO"', source)
        self.assertNotIn('codes.joined(separator: " · ")', source)
        self.assertIn('Image(systemName: "globe")', source)
        # Globe, primary-language shorthand, and chevron share semantic accent color.
        self.assertGreaterEqual(source.count('.foregroundStyle(Color.accentColor)'), 3)
        self.assertIn('Image(systemName: "chevron.right")', source)
        self.assertIn('self.languageSelectionRows', source)
        self.assertNotIn('VStack(alignment: .leading, spacing: 6) { self.languageSelectionRows }', source)
        self.assertNotIn('.frame(height: 31)', source)
        self.assertIn('Label {', source)
        self.assertIn('mode: .ordered(Binding(', source)
        self.assertIn('.accessibilityValue(self.languagePriorityAccessibilityValue)', source)
        self.assertNotIn("DisclosureGroup(isExpanded: self.$showsLanguagePriority)", source)

    def test_heretic_model_scores_are_explicitly_unrated(self):
        card = read("Sayboard/Views/LLMModelCardView.swift")
        variant = read("Shared/LLMConstants.swift")
        self.assertIn('Text("Quality: Unrated")', card)
        self.assertIn('Text("Speed: Unrated")', card)
        self.assertIn('if self.variant.hereticTier != nil', card)
        self.assertIn('ModelStatBars(stats: [', card)
        self.assertIn('case .hereticSmall, .hereticBalanced, .hereticLarge: 0', variant)

    def test_voice_output_failure_reasons_are_enum_only(self):
        diagnostics = read("Shared/FeatureDiagnostics.swift")
        coordinator = read("Sayboard/Services/LLMProcessingCoordinator.swift")
        pipeline = read("Sayboard/Services/SpeechRecognitionService+Transcription.swift")
        self.assertIn('enum FailureReason: String, Codable, Sendable', diagnostics)
        self.assertIn('let failureReason: FailureReason?', diagnostics)
        for reason in ('.busy', '.noTextModel', '.missingModelFile',
                       '.inferenceUnavailable', '.invalidTargetLanguage',
                       '.oversizedOutput'):
            self.assertIn('failureReason: ' + reason, coordinator)
        self.assertIn('failureReason: Task.isCancelled ? nil : .modelLoadFailed', coordinator)
        self.assertIn('failureReason: .inferenceUnavailable', pipeline)
        self.assertNotIn('let rawText: String', diagnostics)
        self.assertNotIn('let transcript: String', diagnostics)

    def test_cancellable_export_and_orphaned_meeting_recovery_warning(self):
        data = read("Sayboard/Services/LocalUserDataStore.swift")
        view = read("Sayboard/Views/DataAndStorageSettingsView.swift")
        meeting = read("Sayboard/Services/MeetingRecordingCoordinator.swift")
        records = read("Sayboard/Views/MeetingRecordsView.swift")
        self.assertIn("withTaskCancellationHandler", data)
        self.assertIn("worker.cancel()", data)
        self.assertGreaterEqual(data.count("try Task.checkCancellation()"), 5)
        self.assertIn("try? fm.removeItem(at: temporary)", data)
        self.assertIn("catch is CancellationError", data)
        self.assertIn("FeatureDiagnostics.record(.data, .cancelled)", data)
        self.assertIn("self.exportTask?.cancel()", view)
        self.assertIn("onDismiss: { self.clearExport() }", view)
        self.assertIn("var unreadable = 0", meeting)
        self.assertIn("record.id == folderID", meeting)
        self.assertIn("self.unreadableRecordCount = unreadable", meeting)
        self.assertIn("FeatureDiagnostics.record(.meeting, .fallback)", meeting)
        self.assertIn("self.recorder.unreadableRecordCount > 0", records)
        self.assertIn("Original files are preserved.", records)

    def test_loading_label_respects_motion_and_storage_warnings(self):
        loading = read("SayboardKeyboard/Views/ModelLoadingLabel.swift")
        self.assertIn("@Environment(\\.accessibilityReduceMotion)", loading)
        self.assertIn(".task(id: self.isLoading && !self.reduceMotion)", loading)
        self.assertIn("self.lowStorage", loading)
        self.assertNotIn("!OperatingSystem.isBackgroundNeuralEngineBlocked", loading)
        self.assertIn(".accessibilityLabel(self.message)", loading)

    def test_lifecycle_timing_does_not_fabricate_physical_results(self):
        trace = read("Shared/KeyboardLifecycleTrace.swift")
        timing = read("Shared/KeyboardLifecycleTiming.swift")
        self.assertIn('"activationTimingReview": activationTimingReview(for: events)', trace)
        self.assertIn('"observedP95AppearanceToCheckpointMs"', trace)
        self.assertIn('"schemaVersion": 9', trace)
        self.assertIn("activeAppearances.removeValue(forKey: signal.session)", timing)
        self.assertIn("subtractingReportingOverflow", timing)
        self.assertIn("guard !numbers.isEmpty else { return nil }", timing)
        self.assertIn("Checkpoints do not prove pixels", trace)

    def test_haptic_reset_and_strength_are_reachable(self):
        settings = read("Sayboard/Views/KeyboardSettingsView.swift")
        shared = read("Shared/SharedSettings.swift")
        self.assertIn("Slider(value: self.$hapticStrength", settings)
        self.assertIn('Text("Haptic Strength")', settings)
        self.assertIn('Button("Reset Haptic Feedback"', settings)
        self.assertIn("SharedSettings.defaultKeyboardHapticStrength", settings)
        self.assertIn("keyboardHapticDriver = .coreHaptics", settings)
        self.assertIn("var keyboardHapticStrength: Double", shared)
        haptics = read("Shared/KeyboardHaptics.swift")
        self.assertIn('unavailableError = "engine-prewarm-failed:', haptics)
        play = haptics.split("static func play(strength:", 1)[1].split(
            "/// The keyboard's standard output", 1
        )[0]
        self.assertLess(
            play.index("if let unavailableError { return unavailableError }"),
            play.index("let newEngine = try CHHapticEngine()")
        )
        self.assertIn("KeyboardSensoryPulse.shared.trigger()", haptics)
        self.assertIn("private static var generation: UInt64", haptics)

    def test_custom_language_edits_are_confirmed(self):
        settings = read("Sayboard/Views/VoiceOutputSettingsView.swift")
        self.assertIn('alert("Other Output Language"', settings)
        self.assertIn('Button("Apply")', settings)
        self.assertIn('Button("Cancel", role: .cancel)', settings)
        self.assertIn("VoiceOutputTarget.customLanguageName(code) != nil", settings)
        other = settings.split('Button("Other language")', 1)[1].split('} label:', 1)[0]
        self.assertIn("self.showCustomLanguagePrompt = true", other)
        self.assertNotIn('self.target = VoiceOutputTarget.custom.rawValue', other)

    def test_speech_model_deep_links_open_model_screen(self):
        tabs = read("Sayboard/Views/MainTabView.swift")
        self.assertIn("private enum SettingsRoute: Hashable", tabs)
        self.assertIn("case .speechModels: ModelsView()", tabs)
        self.assertIn("self.settingsPath.append(SettingsRoute.speechModels)", tabs)
        self.assertIn("case DeepLink.modelsHost:", tabs)
        self.assertEqual(tabs.count(".navigationDestination(for: SettingsRoute.self)"), 2)

    def test_speech_model_filters_are_accessible(self):
        models = read("Sayboard/Views/ModelsView.swift")
        self.assertIn("Clear speech model language filter", models)
        self.assertIn(".frame(minWidth: 44, minHeight: 44)", models)

    def test_meeting_actions_announce_and_preserve_failures(self):
        meetings = read("Sayboard/Views/MeetingRecordsView.swift")
        self.assertIn("self.reduceMotion ? nil : .easeInOut", meetings)
        for label in ("Back 15 seconds", "Forward 15 seconds",
                      "Pause meeting audio", "Play meeting audio",
                      "Transcript incomplete. Original audio parts are preserved."):
            self.assertIn(label, meetings)
        self.assertIn("Unable to save meeting details. Try again.", meetings)
        self.assertIn("self.operationError", meetings)
        self.assertIn("if !self.recorder.deleteRecord(id: id)", meetings)

    def test_compiled_model_cache_requires_confirmation(self):
        data = read("Sayboard/Views/DataAndStorageSettingsView.swift")
        self.assertIn("confirmCacheClear", data)
        self.assertIn('confirmationDialog(\n          "Clear Compiled Model Cache?"', data)
        self.assertIn('Button("Clear Cache", role: .destructive)', data)
        self.assertIn("guard !self.recordingActive, !self.busy else { return }", data)

    def test_keyboard_pulse_animations_honor_reduce_motion_and_teardown(self):
        effects = read("SayboardKeyboard/Views/KeyboardAnimations.swift")
        self.assertGreaterEqual(effects.count("@Environment(\\.accessibilityReduceMotion)"), 2)
        self.assertGreaterEqual(effects.count(".onDisappear {"), 2)
        self.assertIn("guard !self.reduceMotion else { return }", effects)

    def test_storage_warning_is_not_hidden_by_neural_engine_policy(self):
        settings = read("Sayboard/Views/SettingsView.swift")
        self.assertIn("self.showsLowStorageWarning = DiskSpace.isLow()", settings)
        self.assertNotIn("&& !OperatingSystem.isBackgroundNeuralEngineBlocked", settings)

    def test_active_session_failure_is_visible_and_diagnosed(self):
        source = read("Sayboard/Views/SettingsNavigationViews.swift")
        self.assertIn('alert("Active Session Unavailable"', source)
        self.assertIn("try self.speechService.session.startSession()", source)
        self.assertIn("self.activationError = error.localizedDescription", source)
        self.assertIn("FeatureDiagnostics.record(.speech, .failed)", source)
        self.assertNotIn("try? self.speechService.session.startSession()", source)

    def test_keyboard_preview_controls_and_feedback_match_state(self):
        source = read("Sayboard/Views/KeyboardSettingsView.swift")
        self.assertIn('if self.selectedKind == .alphabetic {\n        Toggle("Auto-capitalization"', source)
        self.assertIn('Toggle("Double-Space Period"', source)
        self.assertIn("Tap preview keys to test haptics.", source)
        preview = source.split("private struct KeyboardTestPreview", 1)[1]
        self.assertIn("Button { KeyboardHaptics.key() }", preview)
        self.assertNotIn(".allowsHitTesting(false)", preview)
        self.assertIn(".accessibilityElement(children: .contain)", preview)
        self.assertIn('Image(systemName: image)', preview)
        self.assertIn('Text(verbatim: self.previewUppercase ? title.uppercased() : title.lowercased())', preview)

    def test_preview_has_no_functional_or_duplicate_globe_keys(self):
        settings = read("Sayboard/Views/KeyboardSettingsView.swift")
        phone = read("Sayboard/Views/Onboarding/KeyboardLayoutPreview.swift")
        preview = settings.split("private struct KeyboardTestPreview", 1)[1]
        self.assertEqual(preview.count('if self.systemSwitchRequired && !self.showExtraGlobeKey'), 1)
        self.assertIn("self.emojiPreviewKey", preview)
        self.assertIn("NativeEmojiGlyph()", preview)
        self.assertIn("if self.showExtraGlobeKey", preview)
        self.assertIn("let showExtraGlobeKey: Bool", preview)
        self.assertIn("showExtraGlobeKey: self.showExtraGlobeKey", settings)
        self.assertIn("showExtraGlobeKey", phone)
        self.assertIn(".accessibilityLabel(\"Keyboard preview; tap keys to test haptic feedback\")", preview)
        self.assertNotIn(".allowsHitTesting(false)", preview)

    def test_onboarding_reduce_motion_has_instant_navigation(self):
        source = read("Sayboard/Views/OnboardingView.swift")
        self.assertIn("@Environment(\\.accessibilityReduceMotion) private var reduceMotion", source)
        self.assertIn("self.reduceMotion ? .opacity", source)
        self.assertEqual(source.count("withAnimation(self.reduceMotion ? nil : Self.stepAnimation)"), 2)

    def test_first_install_guide_requires_current_altboard_activation(self):
        guide = read("Sayboard/Views/Onboarding/OnboardingKeyboardView.swift")
        routing = read("Sayboard/Views/OnboardingView.swift")
        progress = read("Sayboard/Helpers/OnboardingProgress.swift")
        self.assertIn("case .add", guide)
        self.assertIn("case .fullAccess", guide)
        self.assertIn("case .test", guide)
        self.assertIn("self.page == .test, isKeyboardTest: true", guide)
        self.assertIn("DarwinNotificationName.keyboardShownInPractice", guide)
        self.assertIn("self.permissionService.keyboardProbeTimestamp >= self.testStartedAt", guide)
        self.assertIn("self.testText = \"\" // Only typing after Altboard opened counts.", guide)
        self.assertIn("self.hasSeenAltboard && self.hasFreshFullAccess", guide)
        self.assertIn("self.confirmedKeyboardVisible", guide)
        self.assertIn("I can see Altboard\'s keys and action bar", guide)
        marker = read("Sayboard/Views/Onboarding/OnboardingTextEntry.swift")
        state = read("SayboardKeyboard/KeyboardState.swift")
        self.assertIn("onboardingKeyboardTestProcessID", marker)
        self.assertIn("isOnboardingKeyboardTestHost", state)
        self.assertIn("case .keyboard: return false", progress)
        self.assertIn("OnboardingKeyboardView { self.pass(.keyboard) }", routing)
        self.assertNotIn("advancesWhenReady", guide)
        setup = read("Sayboard/Views/SetupView.swift")
        self.assertIn('Label("Test Altboard Keyboard", systemImage: "keyboard")', setup)
        self.assertIn("KeyboardSetupGuideRoute()", setup)
        self.assertIn("OnboardingKeyboardView { self.dismiss() }", setup)

    def test_globe_previews_and_fallback_identity_are_kept_in_sync(self):
        phone = read("Sayboard/Views/Onboarding/KeyboardLayoutPreview.swift")
        settings = read("Sayboard/Views/KeyboardSettingsView.swift")
        alphabet = read("SayboardKeyboard/Views/Layouts/AlphabeticKeyboardLayout.swift")
        self.assertIn("showExtraGlobeKey", phone)
        self.assertEqual(phone.count('self.symbolKey("globe", width: Self.sideKeyWidth)'), 3)
        self.assertIn("self.emojiKey(width: 48)", phone)
        self.assertNotIn("nativeGlobeKey(width: 48)", phone)
        self.assertIn('self.symbolKey("sparkles", width: 38)', phone)
        self.assertNotIn("self.showGlobeKey", settings)
        self.assertEqual(settings.count('if self.systemSwitchRequired && !self.showExtraGlobeKey'), 1)
        self.assertIn('self.key("globe", width: 48)', settings)
        self.assertIn("else if SharedSettings().keyboardShowAIButton", alphabet)
        self.assertIn("Output language unavailable. Open Altboard", alphabet)
        self.assertIn("AI actions unavailable. Open Altboard", alphabet)

    def test_off_globe_has_no_fake_in_keyboard_icon_and_on_key_is_leftmost(self):
        chrome = read("SayboardKeyboard/Views/Layouts/KeyboardChrome.swift")
        standard = read("SayboardKeyboard/Views/Layouts/StandardKeyboardLayout.swift")
        extended = read("SayboardKeyboard/Views/Layouts/ExtendedKeyboardLayout.swift")
        alphabet = read("SayboardKeyboard/Views/Layouts/AlphabeticKeyboardLayout.swift")
        phone = read("Sayboard/Views/Onboarding/KeyboardLayoutPreview.swift")
        preview = read("Sayboard/Views/KeyboardSettingsView.swift")
        menu = read("SayboardKeyboard/Views/KeyboardLLMActionsToolbar.swift")
        self.assertIn("self.needsInputModeSwitchKey && !self.showGlobeKey", chrome)
        self.assertIn("if self.keyboardState.showsGlobeButton", chrome)
        self.assertIn("if self.systemSwitchRequired && !self.showExtraGlobeKey", preview)
        self.assertIn("if self.systemSwitchRequired && !self.showExtraGlobeKey", phone)
        self.assertIn("private var showExtraGlobeKey = false", preview)
        self.assertIn("private var showExtraGlobeKey = false", phone)
        for source in (standard, extended, alphabet):
            self.assertLess(source.index("if self.keyboardState.showGlobeKey"),
                            source.index("if self.keyboardState.showSettingsKey"))
        self.assertLess(menu.index("if self.keyboardState.showGlobeKey"),
                        menu.index('KeyButton(content: .systemImage("xmark")'))
        self.assertLess(phone.index("if self.showExtraGlobeKey"),
                        phone.index('self.symbolKey("gearshape"'))
        self.assertNotIn("true // Keep the native keyboard/Emoji picker", chrome)

    def test_live_dictation_first_chunk_and_original_cantonese_script(self):
        live = read("Sayboard/Services/SpeechRecognitionService+ExperimentalLive.swift")
        final = read("Sayboard/Services/SpeechRecognitionService+Transcription.swift")
        policy = read("Shared/LiveDictationChunkPolicy.swift")
        converter = read("Sayboard/Services/CantoneseOutput.swift")
        bridge = read("SayboardKeyboard/KeyboardViewController+ExperimentalLive.swift")
        self.assertIn("static let firstQwenSamples = 24_000", policy)
        self.assertIn("static let subsequentQwenSamples = 24_000", policy)
        self.assertIn("firstCompleted = true", live)
        self.assertIn("if firstChunk && !published", live)
        self.assertIn("retryFirstWindow(after: firstWindow)", live)
        self.assertIn("LiveDictationChunkPolicy.samples(", live)
        self.assertIn("CantoneseOutput.normalizeDictation(", live)
        self.assertIn("CantoneseOutput.normalizeDictation(", final)
        self.assertIn('preferredLanguages.first == "yue"', converter)
        self.assertNotIn("guard settings.voiceOutputTarget == .original else { return }", bridge)
        self.assertIn("proxy.insertText(prefix + update.text)", bridge)
        self.assertIn("guard owned == self.availableDocumentIdentifier()", bridge)
        self.assertIn("FeatureDiagnostics.record(.liveDictation, .firstUpdate,", live)

    def test_listening_animation_respects_accessibility(self):
        chrome = read("SayboardKeyboard/Views/Layouts/KeyboardChrome.swift")
        notice = read("Shared/LiveDictationNotice.swift")
        self.assertIn("AnimatedDictationNoticeLine", chrome)
        self.assertIn("accessibilityReduceMotion", chrome)
        self.assertIn("repeatForever(autoreverses: true)", chrome)
        self.assertIn(".onDisappear { self.bouncing = false }", chrome)
        self.assertIn("Listening…", notice)
        self.assertIn("tidy afterwards", notice)

    def test_settings_follow_user_tasks(self):
        home = read("Sayboard/Views/SettingsView.swift")
        for heading in ('Section("Speech & AI")', 'Text("App")'):
            self.assertIn(heading, home)
        for path in ("SpeechLanguagesSettingsView(", "DictationSettingsView(inline: true)",
                     "LLMSettingsView(inline: true)",
                     "KeyboardSettingsView(", "DataAndStorageSettingsView(inline: true)", "LLMModelsScreen()",
                     "AppLanguageListView()", "DiagnosticsView()"):
            self.assertIn(path, home)
        self.assertNotIn("DictationSettingsView()", home)
        self.assertIn("Altboard-Canto · Source on GitHub", home)
        self.assertNotIn('Section("Start Here")', home)
        self.assertNotIn('Is My Microphone Ready?', home)
        self.assertIn('ActiveSessionToggle()', home)
        layout = read("Sayboard/Views/KeyboardSettingsView.swift")
        self.assertIn('KeyboardCustomizationView(\n          inline: true,', layout)
        self.assertNotIn('KeyboardCustomizationView(', home)
        self.assertIn('Label("History & Storage", systemImage: "externaldrive")', home)
        self.assertNotIn('VoiceOutputSettingsView()', home)
        self.assertEqual(home.count("ActiveSessionToggle()"), 1)
        self.assertNotIn("ActiveSessionToggle()", read("Sayboard/Views/SettingsNavigationViews.swift"))
        self.assertIn('selectedKind: self.keyboardKindBinding, inline: true', home)

    def test_inline_actions_and_test_field_clear(self):
        home = read("Sayboard/Views/SettingsView.swift")
        history = read("Sayboard/Views/HistoryListView.swift")
        ai = read("Sayboard/Views/LLMSettingsView.swift")
        self.assertEqual(home.count("DisclosureGroup(isExpanded: self.$showsDictation)"), 1)
        self.assertEqual(home.count("DisclosureGroup(isExpanded: self.$showsAIActions)"), 1)
        self.assertEqual(home.count("DictationSettingsView(inline: true)"), 1)
        self.assertEqual(home.count("LLMSettingsView(inline: true)"), 1)
        self.assertNotIn('Toggle("Enabled", isOn: self.$llmEnabled)', ai)
        self.assertIn('LabeledContent("Writing Modes")', ai)
        self.assertIn('Label("Rewrite & Translate"', home)
        self.assertIn('self.isKeyboardTestFocused = false\n        self.keyboardTestingText = ""', history)
        self.assertIn('"Close test keyboard and clear test text"', history)
        self.assertIn("Settings → Speech & AI → Speech Model",
                      read("Sayboard/Views/MeetingRecordsView.swift"))

    def test_sections_with_footers_use_explicit_headers(self):
        sections = {
            "Sayboard/Views/SettingsView.swift": ("App",),
            "Sayboard/Views/LearningDataSettingsView.swift":
                ("Learned Suggestions", "Your Data"),
        }
        for path, titles in sections.items():
            source = read(path)
            for title in titles:
                with self.subTest(path=path, section=title):
                    self.assertNotIn('Section("' + title + '") {', source)
                    self.assertIn('Text("' + title + '")', source)
                    self.assertIn('} header: {', source)
                    self.assertIn('} footer: {', source)

    def test_keyboard_options_are_not_a_flat_settings_page(self):
        layout = read("Sayboard/Views/KeyboardSettingsView.swift")
        custom = read("Sayboard/Views/KeyboardCustomizationView.swift")
        self.assertIn('Label("Keyboard Type"', layout)
        self.assertIn('Label("Key Order"', layout)
        self.assertIn('Text("German (Ä Ö Ü ß)")', layout)
        self.assertIn(".pickerStyle(.menu)", layout)
        self.assertIn("KeyboardTestPreview(", layout)
        self.assertNotIn('Text("Preview")', layout)
        self.assertEqual(layout.count("    Section {"), 1)
        self.assertLess(layout.index('Label("Key Order"'), layout.index('Label("Keyboard Customization"'))
        self.assertLess(layout.index('Label("Keyboard Customization"'), layout.index("KeyboardTestPreview("))
        self.assertNotIn("Section(", custom)
        self.assertNotIn("Slider(", custom)
        self.assertNotIn('Text("Strength")', custom)
        for control in ('Auto-capitalization', 'Double-Space Period', 'Haptic Feedback'):
            self.assertIn('Toggle("' + control, layout)
            self.assertNotIn('Toggle("' + control, custom)
        for control in ('Extra Globe Key', 'Settings Key', 'Output Key', 'AI Key'):
            self.assertIn('Toggle("' + control, custom)
        self.assertNotIn('.disabled(!self.aiEnabled)', custom)
        self.assertIn("Tap preview keys to test haptics.", layout)
        self.assertEqual(layout.count('if self.systemSwitchRequired && !self.showExtraGlobeKey'), 1)
        self.assertIn("if self.showExtraGlobeKey", layout)
        self.assertNotIn('Text("Not yet available")', custom)

    def test_settings_routes_have_single_owners(self):
        routes = read("Sayboard/Views/SettingsNavigationViews.swift")
        output = read("Sayboard/Views/VoiceOutputSettingsView.swift")
        ai = read("Sayboard/Views/LLMSettingsView.swift")
        models = read("Sayboard/Views/ModelsView.swift")
        languages = read("Sayboard/Views/SpeechLanguagesSettingsView.swift")
        self.assertNotIn("ModelsView()", routes + output + languages)
        self.assertNotIn("LLMModelsScreen()", output + languages)
        self.assertNotIn("self.modelsSection", ai)
        self.assertNotIn("LLMModelsSection()", models)
        self.assertNotIn("languagePrefVariant", models)
        self.assertIn("mode: .ordered(", languages)
        self.assertNotIn("updated.subtracting", languages)

    def test_native_emoji_switcher_and_opt_in_top_globe(self):
        keyboard = read("SayboardKeyboard/Views/Layouts/KeyboardChrome.swift")
        state = read("SayboardKeyboard/KeyboardState.swift")
        config = read("Shared/SharedSettings.swift")
        preview = read("Sayboard/Views/KeyboardSettingsView.swift")
        controller = read("SayboardKeyboard/KeyboardViewController.swift")
        custom = read("Sayboard/Views/KeyboardCustomizationView.swift")
        native = read("SayboardKeyboard/Views/NativeInputModeSwitchKey.swift")
        alphabet = read("SayboardKeyboard/Views/Layouts/AlphabeticKeyboardLayout.swift")
        self.assertNotIn("keyboardGlobeTemporarilyDisabled", config + keyboard + preview + controller + custom)
        self.assertIn("var keyboardShowGlobeKey: Bool", config)
        self.assertIn("self.showGlobeKey = self.settings.keyboardShowGlobeKey", state)
        self.assertIn('@Binding var showGlobe: Bool', custom)
        self.assertIn('showGlobe: self.$showExtraGlobeKey', preview)
        self.assertIn('Toggle("Extra Globe Key", isOn: self.$showGlobe)', custom)
        self.assertIn("var showsGlobeButton: Bool", keyboard)
        self.assertIn("self.needsInputModeSwitchKey && !self.showGlobeKey", keyboard)
        self.assertIn("var needsInputModeSwitchKey: Bool", config)
        self.assertIn("if self.keyboardState.showsGlobeButton", keyboard)
        self.assertIn('iconName = "globe"', native)
        self.assertIn('self.key("globe", width: 48)', preview)
        bottom = keyboard.split("struct KeyboardBottomRow: View", 1)[1]
        emoji = bottom.split("if self.onEmojiAction != nil", 1)[1].split(
            "} else if self.keyboardState.showsGlobeButton", 1
        )[0]
        self.assertIn("NativeInputModeSwitchKey(", emoji)
        self.assertIn('iconName: "nativeEmoji"', emoji)
        self.assertIn("configure: self.keyboardState.configureInputModeListButton", emoji)
        self.assertNotIn("openEmoji()", emoji)
        self.assertNotIn("KeyButton(", emoji)
        self.assertIn('var onEmojiAction:', keyboard)
        # The old page still exists in a cross-worker file, but the key must
        # never invoke its callback. Removal belongs to integration.
        self.assertIn('onEmojiAction: { self.openEmojiPage() }', alphabet)
        self.assertIn('keyboardState.effectiveTypingKind == .alphabetic', keyboard)
        self.assertIn('Label("Writing Style", systemImage: "text.alignleft")',
                      read("Sayboard/Views/LLMSettingsView.swift"))
        storage = read("Sayboard/Views/DataAndStorageSettingsView.swift")
        self.assertGreaterEqual(storage.count(".frame(minHeight: 64)"), 3)
        self.assertIn('iconName: "globe"', alphabet)
        self.assertIn('if self.keyboardState.showGlobeKey', alphabet)
        self.assertLess(alphabet.index('if self.keyboardState.showGlobeKey'),
                        alphabet.index('if self.keyboardState.showSettingsKey'))
        self.assertEqual(preview.count("if self.systemSwitchRequired"), 1)
        self.assertIn('if self.showExtraGlobeKey || self.systemSwitchRequired', preview)
        self.assertIn("NativeInputModeSwitchKey(", keyboard)
        self.assertIn("self.keyboardState.needsInputModeSwitchKey",
          read("SayboardKeyboard/Views/KeyboardLLMActionsToolbar.swift"))
        self.assertIn("SharedKey.needsInputModeSwitchKey", preview)
        self.assertIn("SharedKey.keyboardShowGlobeKey",
          read("Sayboard/Views/Onboarding/KeyboardLayoutPreview.swift"))
        self.assertIn("#selector(handleInputModeList(from:with:))", controller)
        self.assertIn("for: .allTouchEvents", controller)
        self.assertIn("button.removeTarget(self", controller)
        self.assertIn("button.addTarget(", controller)
        self.assertIn("configure?(button)", native)
        self.assertIn("NativeEmojiGlyph().path(in:", native)
        self.assertIn("button.isAccessibilityElement = true", native)

    def test_output_and_formatting_have_one_owner(self):
        dictation = read("Sayboard/Views/SettingsNavigationViews.swift")
        actions = read("Sayboard/Views/LLMSettingsView.swift")
        output = read("Sayboard/Views/VoiceOutputSettingsView.swift")
        formatting = read("Sayboard/Views/TextOutputSection.swift")
        self.assertIn("DisclosureGroup(isExpanded: self.$showsOutput)", dictation)
        self.assertIn("VoiceOutputSettingsView(inline: true)", dictation)
        self.assertNotIn("VoiceOutputSettingsView(", actions)
        self.assertIn("DisclosureGroup(isExpanded: self.$showsFormatting)", actions)
        self.assertEqual(actions.count("TextOutputSection(inline: true)"), 1)
        self.assertNotIn("TextOutputSection(", output)
        self.assertIn("var inline = false", formatting)
        self.assertIn("var inline = false", output)
        self.assertGreater(actions.index("TextOutputSection(inline: true)"),
                           actions.index('Picker("Long Press Action"'))
        self.assertIn('Label("Per-App Style"', formatting)
        self.assertNotIn('Auto-Copy to Clipboard', formatting)
        self.assertIn('Label("Include Punctuation"', output)
        self.assertIn('Text(verbatim: self.currentOutputAbbreviation)', output)
        self.assertIn('WordCorrectionsView()', dictation)
        self.assertNotIn('Enable Meeting Recording', dictation)

    def test_dictation_final_output_and_ai_key_are_consistent(self):
        settings = read("Shared/SharedSettings.swift")
        speech = read("Sayboard/Services/SpeechRecognitionService+Transcription.swift")
        keyboard = read("SayboardKeyboard/KeyboardViewController.swift")
        llm_keyboard = read("SayboardKeyboard/KeyboardViewController+LLM.swift")
        output = read("Sayboard/Views/VoiceOutputSettingsView.swift")
        language_button = read("SayboardKeyboard/Views/TranslateToggleButton.swift")
        self.assertIn('voicePunctuationEnabled', settings)
        self.assertIn('VoicePunctuationPolicy.render(', speech)
        self.assertIn('get { self.keyboardShowAIButton }', settings)
        self.assertIn('abbreviatedLabel(customLanguage:', language_button)
        self.assertIn('Menu {', output)
        self.assertNotIn('copyFinalTextToClipboardIfEnabled', keyboard + llm_keyboard)
        self.assertIn('UIPasteboard.general.string = result', llm_keyboard)

    def test_unified_word_corrections_and_output_independence(self):
        word = read("Sayboard/Views/WordCorrectionsView.swift")
        languages = read("Sayboard/Views/SpeechLanguagesSettingsView.swift")
        output = read("Sayboard/Views/VoiceOutputSettingsView.swift")
        self.assertIn("private var combinedEntries: [Entry]", word)
        self.assertIn("ForEach(self.combinedEntries)", word)
        self.assertIn("settings.cantoneseCorrectionRules = updated", word)
        self.assertIn("settings.snippets = updated", word)
        self.assertIn("settings.snippets = settings.snippets.filter", word)
        self.assertIn("CantoneseCorrectionsView()", word)
        self.assertIn("SnippetsView()", word)
        self.assertNotIn("settings.voiceOutputTarget = .original", languages)
        self.assertIn("LocalizedStringKey(option.title)", output)

    def test_no_custom_swipe_to_switch_app_tabs(self):
        tabs = read("Sayboard/Views/MainTabView.swift")
        self.assertNotIn("pageSwipe(for:", tabs)
        self.assertNotIn("AppPageSwipe.destination(", tabs)
        self.assertEqual(tabs.count("TabView(selection: self.$selectedTab)"), 2)

    def test_host_keeps_render_tree_across_focus_changes(self):
        controller = read("SayboardKeyboard/KeyboardViewController.swift")
        self.assertIn("UIHostingController<KeyboardView>", controller)
        self.assertNotIn("KeyboardHostingRoot", controller)
        self.assertNotIn("controller.rootView =", controller)
        self.assertNotIn("rootNeedsMeasuredRemount", controller)
        appear = controller.split("override func viewWillAppear(", 1)[1].split(
            "override func viewWillDisappear(", 1)[0]
        self.assertIn("if self.hostingController == nil", appear)
        self.assertEqual(appear.count("self.setupKeyboardView()"), 1)
        setup = controller.split("private func setupKeyboardView()", 1)[1].split(
            "private func applyKeyboardHeight()", 1)[0]
        self.assertIn("guard self.hostingController == nil else { return }", setup)
        self.assertIn("hosting.view.bottomAnchor.constraint(equalTo: self.view.bottomAnchor)", setup)
        self.assertIn("keyboardAppearanceRevision &+= 1", controller)

    def test_meeting_tab_uses_existing_local_recorder(self):
        tabs = read("Sayboard/Views/MainTabView.swift")
        meeting = read("Sayboard/Views/MeetingRecordsView.swift")
        recording = read("Sayboard/Services/MeetingRecordingCoordinator.swift")
        self.assertIn('Tab("Meetings"', tabs)
        self.assertNotIn('Tab("Models"', tabs)
        # Test the action and state-dependent accessible label, not an icon asset.
        self.assertIn("self.recordAction()", meeting)
        self.assertIn('self.recorder.isRecording ? "Stop and save meeting" : "Start a new meeting"', meeting)
        self.assertIn("self.recorder.stop()", meeting)
        self.assertIn("self.recorder.start(with: self.speechService)", meeting)
        self.assertIn(".searchable(", meeting)
        self.assertIn('Image(systemName: "gobackward.15")', meeting)
        self.assertIn('Image(systemName: "goforward.15")', meeting)
        self.assertIn("MeetingAudioPlayback()", meeting)
        self.assertIn("sequenceNumber", recording)
        self.assertNotIn("SharedSettings().experimentalMeetingRecordEnabled", recording)
        self.assertIn("static let partDuration: TimeInterval = 15 * 60", recording)
        self.assertIn("static let updateSeconds = 8", recording)

    def test_live_default_uses_model_and_memory_and_retains_explicit_choice(self):
        shared = read("Shared/SharedSettings.swift")
        view = read("Sayboard/Views/SettingsNavigationViews.swift")
        self.assertIn("ProcessInfo.processInfo.physicalMemory >= 8 * 1_073_741_824", shared)
        self.assertIn("defaults.object(forKey: SharedKey.experimentalLiveDictationEnabled)", shared)
        self.assertIn("SharedSettings().experimentalLiveDictationEnabled = enabled", view)
        self.assertIn("guard self.experimentalLiveEnabled != enabled", view)

    def test_history_only_deletes_voice_notes(self):
        history = read("Sayboard/Views/HistoryStorageSettingsView.swift")
        categories = read("Sayboard/Views/DataAndStorageSettingsView.swift")
        self.assertIn("Delete Voice Notes", history)
        self.assertIn("Meetings, learned suggestions and downloaded models are not affected",
                      history)
        self.assertNotIn("NavigationLink", categories)
        for label in ("Export All Data", "Delete All Data"):
            self.assertIn(label, categories)
        self.assertIn("recordingActive", categories)
        store = read("Sayboard/Services/LocalUserDataStore.swift")
        self.assertIn("recorder.deleteAllRecords()", store)
        self.assertIn("try fm.zipItem(at:", store)

    def test_user_initiated_export_includes_explicit_corrections(self):
        export = read("Shared/PersonalVocabularyExport.swift")
        settings = read("Sayboard/Views/LearningDataSettingsView.swift")
        self.assertIn("schemaVersion: 3", export)
        self.assertIn("manualSpeechCorrections", export)
        store = read("Sayboard/Services/LocalUserDataStore.swift")
        self.assertIn("cantoneseCorrectionRules.map", store)
        self.assertIn("LatinSpeechCorrectionLearning.read", store)
        self.assertIn("ConfirmedChoiceLearning.chineseCounts", store)
        self.assertIn("LocalUserDataStore.vocabularyData()", settings)
        self.assertIn("self.showExporter = true", settings)

    def test_universal_cantonese_diagnostics_preserved(self):
        diagnostics = read("Sayboard/Views/DiagnosticsView.swift")
        model = read("Shared/CantoneseSchemePreference.swift")
        self.assertIn("CantoneseRomanizationDiagnosticsView()", diagnostics)
        self.assertIn("recent_weighted_counts", model)
        self.assertIn("recording_or_transcript_included", model)

    def test_explicit_unknown_word_learning_remains(self):
        suggestions = read("SayboardKeyboard/LatinWordSuggestions.swift")
        keyboard = read("SayboardKeyboard/Views/Layouts/AlphabeticKeyboardLayout.swift")
        self.assertIn("func rememberCustom(_ word: String, preferred: [String]) -> Bool",
                      suggestions)
        self.assertIn("let learnable = self.learnableLatinWord", keyboard)
        self.assertIn("expandedLatinCandidateGrid", keyboard)


if __name__ == "__main__":
    unittest.main()




