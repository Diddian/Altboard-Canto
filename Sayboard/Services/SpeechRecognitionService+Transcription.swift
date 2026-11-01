
import Accelerate
import Foundation

extension SpeechRecognitionService {

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
    let engine = self.settings.selectedVariant.engine
    let loadState = String(describing: self.activeLoadState)

    guard !samples.isEmpty else {
      DiagnosticLog.write("transcribe: ABORT — 0 samples reached the model")
      self.settings.lastDictationOutcome = .engineFailed
      return
    }

    self.reportSignalStats(samples: samples, engine: String(describing: engine), loadState: loadState)
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

    DictationBreadcrumb.record(
      "asr: \(String(describing: engine)) completed in \(String(format: "%.1f", CFAbsoluteTimeGetCurrent() - recognitionStarted))s"
    )

    switch result {
    case .text: self.settings.lastDictationOutcome = nil
    case .noSpeech: self.settings.lastDictationOutcome = .noSpeech
    case .failed: self.settings.lastDictationOutcome = .engineFailed
    }

    if case .text(let output) = result {
      let rawText = CantoneseOutput.normalize(TextSanitizer.sanitize(output.text))
      guard !rawText.isEmpty else {
        self.settings.lastDictationOutcome = .noSpeech
        return
      }
      self.currentRawTranscription = rawText
      if let unexpected = PreferredVoiceLanguages.unexpectedScript(
        in: rawText, allowed: self.recordingSpokenLanguages
      ) {
        self.settings.lastDictationOutcome = .unexpectedLanguage
        DiagnosticLog.write(
          "asr: refused unexpected script '\(unexpected)' not among user's preferred languages"
        )
        return
      }

      // Preview is the unmodified ASR result. It is not inserted into
      // the host app before translation/cleanup completes.
      let target = self.recordingOutputOptions.target
      let stage: VoiceProcessingStage = target != .original ? .translating
        : (self.recordingOutputOptions.needsLLM ? .editing : .finalizing)
      TranscriptionBridge.writeVoiceProgress(stage, rawPreview: rawText)

      // A conservative built-in greeting correction and editable local
      // phrase rules run independently of the optional offline LLM.
      self.settings.synchronize()
      let savedCorrections = self.settings.cantoneseCorrectionRules
      let corrections = CantoneseCorrections.applyDetailed(
        rawText, customRules: savedCorrections
      )
      let correctedText = corrections.text
      DiagnosticLog.write(
        "voice: saved correction rules=\(savedCorrections.count) matches=\(corrections.matchedRules)"
      )
      let options = self.recordingOutputOptions
      self.settings.lastVoiceOutputProcessed = options.needsLLM
      var finalText = correctedText
      if options.needsLLM {
        let processed = await self.llmCoordinator?.processVoiceDictation(correctedText, options: options)
        if let processed, !processed.isEmpty {
          finalText = processed
        } else if options.target != .original {
          // Explicit language must not silently fall back to untranslated text.
          self.settings.lastDictationOutcome = .processingFailed
          DiagnosticLog.write("voice: selected output language failed; raw speech retained in history")
          return
        }
      }
      // The user's corrections MUST be the last text operation before the
      // bridge. Foundation's Hans-Hant transliterator turns the valid Hong
      // Kong greeting 喂 back into 餵, even after earlier corrections.
      let displayText = TechnicalTextFormatter.format(CantoneseOutput.normalize(finalText))
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
        bridgeText = styledText
      }
      TranscriptionBridge.writeVoiceProgress(.finalizing)
      self.currentTranscription = bridgeText

      self.settings.chargeFreeWords(WordCounter.count(bridgeText))

      TranscriptionBridge.writeTranscription(bridgeText)

      if let start = output.firstWordStart, let end = output.lastWordEnd {
        self.currentWordBoundaries = (start: start, end: end)
      } else {
        self.currentWordBoundaries = nil
      }

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
    )
    HistoryStore.shared.saveRecord(record)
    HistoryStore.shared.applyRetentionPolicy()
    self.currentAudioFileName = nil
    self.historySaveGeneration += 1
  }
}
