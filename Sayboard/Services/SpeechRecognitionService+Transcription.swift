
import Accelerate
import Foundation

extension SpeechRecognitionService {

  func isCurrentDictation(_ token: String?) -> Bool {
    self.settings.synchronize()
    let current = DictationRequestPolicy.isCurrent(
      started: token, current: self.settings.dictationSessionToken,
      cancelled: self.settings.dictationCancellationRequested
    )
    if !current {
      if token != nil && token == self.settings.dictationSessionToken {
        self.cancelRecording()
      } else {
        FeatureDiagnostics.record(.speech, .cancelled)
      }
    }
    return current
  }

  func reportSignalStats(samples: [Float], engine: String, loadState: String) {
    var peak: Float = 0
    var mean: Float = 0
    vDSP_maxmgv(samples, 1, &peak, vDSP_Length(samples.count))
    vDSP_rmsqv(samples, 1, &mean, vDSP_Length(samples.count))
    let assumedDuration = Double(samples.count) / 16_000
    DiagnosticLog.write(
      "transcribe: engine=\(engine) load=\(loadState) samples=\(samples.count) "
        + "peak=\(peak) rms=\(mean) assumedDuration=\(String(format: "%.2f", assumedDuration))s"
    )
  }

  func styled(_ text: String, host: String?) -> String {
    let resolvedStyle = AppStyleStore().resolvedStyle(
      hostBundleId: host,
      defaultStyle: self.settings.defaultWritingStyle,
    )
    let formatted = TextStyleFormatter.format(text, style: resolvedStyle)
    return SnippetExpander.expand(formatted, snippets: self.settings.snippets)
  }

  func runFinalTranscription(samples: [Float], stylingHost: String?) async {
    let requestToken = self.settings.dictationSessionToken
    guard self.isCurrentDictation(requestToken) else { return }
    let engine = self.settings.selectedVariant.engine
    let loadState = String(describing: self.activeLoadState)

    guard !samples.isEmpty else {
      FeatureDiagnostics.record(.speech, .failed)
      DiagnosticLog.write("transcribe: ABORT — 0 samples reached the model")
      self.settings.lastDictationOutcome = .engineFailed
      return
    }

    self.reportSignalStats(samples: samples, engine: String(describing: engine), loadState: loadState)
    FeatureDiagnostics.record(.speechAudio, .completed, durationMs: samples.count / 16)
    let recognitionStarted = CFAbsoluteTimeGetCurrent()

    let result: TranscriptionResult =
      switch engine {
      case .whisperKit:
        await self.whisperService.transcribe(audioSamples: samples)
      case .parakeet:
        await self.parakeetService.transcribe(audioSamples: samples)
      case .moonshine:
        await self.moonshineService.transcribe(audioSamples: samples)
      case .qwen3:
        await self.qwen3Service.transcribe(audioSamples: samples)
      }

    let decodeDurationMs = Int((CFAbsoluteTimeGetCurrent() - recognitionStarted) * 1_000)
    let decodeEvent: FeatureDiagnostics.Event
    switch result {
    case .text: decodeEvent = .completed
    case .noSpeech: decodeEvent = .noSpeech
    case .failed: decodeEvent = .failed
    }
    FeatureDiagnostics.record(
      .speechDecode, decodeEvent, durationMs: decodeDurationMs,
      speechEngine: FeatureDiagnostics.SpeechEngine(rawValue: String(describing: engine)),
      audioDurationMs: samples.count / 16, residentMB: ProcessFootprint.residentMB()
    )
    guard self.isCurrentDictation(requestToken) else { return }
    DictationBreadcrumb.record(
      "asr: \(String(describing: engine)) completed in \(String(format: "%.1f", Double(decodeDurationMs) / 1_000))s"
    )

    switch result {
    case .text: self.settings.lastDictationOutcome = nil
    case .noSpeech:
      self.settings.lastDictationOutcome = .noSpeech
      FeatureDiagnostics.record(.speech, .noSpeech)
    case .failed:
      self.settings.lastDictationOutcome = .engineFailed
      FeatureDiagnostics.record(.speech, .failed)
    }

    if case .text(let output) = result {
      let rawText = CantoneseOutput.normalize(TextSanitizer.sanitize(output.text))
      guard !rawText.isEmpty else {
        self.settings.lastDictationOutcome = .noSpeech
        FeatureDiagnostics.record(.speech, .noSpeech)
        return
      }
      self.currentRawTranscription = rawText
      if let unexpected = PreferredVoiceLanguages.unexpectedScript(
        in: rawText, allowed: self.recordingSpokenLanguages
      ) {
        self.settings.lastDictationOutcome = .unexpectedLanguage
        FeatureDiagnostics.record(.speech, .rejected)
        DiagnosticLog.write(
          "asr: refused unexpected script '\(unexpected)' not among user's preferred languages"
        )
        return
      }

      // Recognition languages are captured for this recording, but output
      // preferences are live App Group settings. A later language selection
      // must override the preference present when microphone capture began.
      self.settings.synchronize()
      let savedCorrections = self.settings.cantoneseCorrectionRules
      let corrections = CantoneseCorrections.applyDetailed(
        rawText, customRules: savedCorrections
      )
      let correctedText = LatinSpeechCorrectionLearning.apply(
        corrections.text,
        languages: self.recordingSpokenLanguages,
        defaults: AppGroup.sharedDefaults
      )
      DiagnosticLog.write(
        "voice: saved correction rules=\(savedCorrections.count) matches=\(corrections.matchedRules)"
      )

      var deliveredText: String?
      for attempt in 1...VoiceOutputSelectionPolicy.maximumAttempts {
        self.settings.synchronize()
        let options = self.settings.voiceOutputConfiguration
        let stage: VoiceProcessingStage = options.target != .original ? .translating
          : (options.needsLLM ? .editing : .finalizing)
        // Live dictation remains in the spoken language. Only the final
        // bridge result is translated or cleaned, never the raw preview.
        TranscriptionBridge.writeVoiceProgress(stage, rawPreview: rawText)

        var finalText = correctedText
        var modelOutputMissing = false
        if options.needsLLM {
          let processed = await self.llmCoordinator?.processVoiceDictation(
            correctedText, options: options
          )
          if let processed, !processed.isEmpty {
            finalText = processed
          } else {
            modelOutputMissing = true
          }
        }

        guard self.isCurrentDictation(requestToken) else { return }
        // Offline model loading/inference may take long enough for another
        // language tap. Never insert output generated for an obsolete target.
        self.settings.synchronize()
        switch VoiceOutputSelectionPolicy.decide(
          processed: options, current: self.settings.voiceOutputConfiguration,
          attempt: attempt
        ) {
        case .retry:
          FeatureDiagnostics.record(.voiceOutput, .interrupted)
          DiagnosticLog.write("voice: output preference changed during processing; retrying")
          continue
        case .reject:
          FeatureDiagnostics.record(.voiceOutput, .rejected)
          self.settings.lastDictationOutcome = .processingFailed
          DiagnosticLog.write("voice: repeated output changes prevented safe delivery")
          return
        case .deliver:
          break
        }

        if modelOutputMissing && options.target != .original {
          // An explicit translation must never fall back to spoken-language text.
          self.settings.lastDictationOutcome = .processingFailed
          FeatureDiagnostics.record(.voiceOutput, .failed)
          DiagnosticLog.write("voice: selected output language unavailable; raw speech retained in history")
          return
        }

        // Corrections are applied after display normalization for original /
        // Cantonese targets, preserving the Hong Kong greeting 喂.
        let displayText = TechnicalTextFormatter.format(
          CantoneseOutput.normalizeForOutput(finalText, options: options)
        )
        let styledText = self.styled(displayText, host: stylingHost)
        let bridgeText: String
        switch options.target {
        case .original, .cantonese, .traditionalChinese:
          let finalCorrection = CantoneseCorrections.applyDetailed(
            styledText, customRules: savedCorrections
          )
          bridgeText = finalCorrection.text
          DiagnosticLog.write("voice: final user correction matches=\(finalCorrection.matchedRules)")
        default:
          bridgeText = options.isSimplifiedChinese
            ? VoiceOutputScriptPolicy.simplify(styledText) : styledText
        }

        // Recheck immediately before the irreversible app-to-keyboard handoff.
        // Excessive changes fail closed rather than committing stale language.
        self.settings.synchronize()
        switch VoiceOutputSelectionPolicy.decide(
          processed: options, current: self.settings.voiceOutputConfiguration,
          attempt: attempt
        ) {
        case .retry:
          FeatureDiagnostics.record(.voiceOutput, .interrupted)
          DiagnosticLog.write("voice: output preference changed before delivery; retrying")
          continue
        case .reject:
          FeatureDiagnostics.record(.voiceOutput, .rejected)
          self.settings.lastDictationOutcome = .processingFailed
          DiagnosticLog.write("voice: output preference changed too often to deliver")
          return
        case .deliver:
          break
        }

        self.settings.lastVoiceOutputProcessed = options.needsLLM
        TranscriptionBridge.writeVoiceProgress(.finalizing)
        let finalOutput = VoicePunctuationPolicy.render(
          bridgeText, enabled: options.punctuationEnabled
        )
        self.currentTranscription = finalOutput
        self.settings.chargeFreeWords(WordCounter.count(finalOutput))
        TranscriptionBridge.writeTranscription(finalOutput)
        deliveredText = finalOutput
        break
      }
      guard let bridgeText = deliveredText else {
        self.settings.lastDictationOutcome = .processingFailed
        FeatureDiagnostics.record(.voiceOutput, .failed)
        return
      }

      if let start = output.firstWordStart, let end = output.lastWordEnd {
        self.currentWordBoundaries = (start: start, end: end)
      } else {
        self.currentWordBoundaries = nil
      }

      FeatureDiagnostics.record(.speech, .completed,
        durationMs: Int((CFAbsoluteTimeGetCurrent() - recognitionStarted) * 1_000))
      DiagnosticLog.write("transcribe: SUCCESS \(bridgeText.count) chars -> bridge")
    } else {
      self.currentWordBoundaries = nil
      let reason = if case .failed(let message) = result { message } else { "no speech detected" }
      DiagnosticLog.write("transcribe: NO TEXT — \(reason)")
    }
  }

  func saveHistoryRecord() {
    guard let fileName = currentAudioFileName else { return }
    guard let result = audioRecorder.stopRecording() else { return }
    if result.writeFailed {
      FeatureDiagnostics.record(.speech, .fallback)
      DictationBreadcrumb.record("history: incomplete audio file discarded; text delivery unaffected")
      try? FileManager.default.removeItem(at: result.url)
      self.currentAudioFileName = nil
      return
    }

    let transcription = self.currentTranscription.isEmpty ? self.currentRawTranscription : self.currentTranscription
    guard !transcription.isEmpty else {
      if let url = HistoryStore.shared.audioFileURL(for: fileName) {
        try? FileManager.default.removeItem(at: url)
      }
      return
    }

    var duration = result.duration
    var waveformSamples = result.waveformSamples

    if let bounds = currentWordBoundaries {
      if
        let trimResult = AudioTrimmer.trimToSpeech(
          fileURL: result.url,
          firstWordStart: bounds.start,
          lastWordEnd: bounds.end,
        )
      {
        duration = trimResult.duration
        waveformSamples = trimResult.waveformSamples
      }
    }
    self.currentWordBoundaries = nil

    let record = HistoryRecord(
      id: UUID(),
      date: Date(),
      duration: duration,
      transcription: transcription,
      audioFileName: fileName,
      waveformSamples: waveformSamples,
      originalASR: self.currentRawTranscription.isEmpty ? nil : self.currentRawTranscription,
      recognitionLanguages: self.recordingSpokenLanguages
    )
    HistoryStore.shared.saveRecord(record)
    HistoryStore.shared.applyRetentionPolicy()
    self.currentAudioFileName = nil
    self.historySaveGeneration += 1
  }
}

