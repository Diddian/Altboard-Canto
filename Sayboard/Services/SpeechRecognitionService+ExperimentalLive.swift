import Foundation

extension SpeechRecognitionService {
  /// Called after capture has started. This uses the existing microphone tap.
  func startExperimentalLiveIfNeeded() {
    guard self.settings.experimentalLiveDictationEnabled,
          self.settings.selectedVariant.engine == .qwen3,
          let token = self.settings.dictationSessionToken,
          !token.isEmpty, self.experimentalLiveTask == nil else { return }
    self.liveDictationStatus = "Waiting for first audio chunk and Qwen model"
    FeatureDiagnostics.record(.liveDictation, .started)
    let liveStartedAt = CFAbsoluteTimeGetCurrent()
    self.experimentalLiveTask = Task { @MainActor [weak self] in
      guard let self else { return }
      var readOffset = 0
      var revision = 0
      var combined = ""
      var reportedSlow = false
      var hasAttemptedFirst = false
      // Shorten first-text capture delay without starting concurrent 1.7B
      // inference jobs. Native offline decode time remains device-dependent.
      // A 1.5-second first chunk restores the earlier reliable recognizer context.
      // Inference stays serialized and decode time remains device-dependent.
      while !Task.isCancelled && self.isRecording {
        let frameCount = LiveDictationChunkPolicy.samples(
          isQwen: true, hasAttemptedFirst: hasAttemptedFirst
        )
        guard self.activeLoadState == .loaded,
              let samples = self.accumulator.chunk(from: readOffset, count: frameCount)
        else {
          do { try await Task.sleep(for: .milliseconds(120)) }
          catch { break }
          continue
        }
        readOffset += samples.count
        let firstChunk = !hasAttemptedFirst
        hasAttemptedFirst = true
        self.liveDictationStatus = "Transcribing live segment"
        let started = CFAbsoluteTimeGetCurrent()
        let result = await self.transcribeSamples(samples)
        guard !Task.isCancelled, self.isRecording else { break }
        if case .text(let output) = result {
          // The native Qwen decoder may prefix each chunk with a language
          // header. Clean every chunk before it reaches the host input field.
          let cleaned = CantoneseOutput.normalizeDictation(
            TextSanitizer.sanitize(output.text),
            options: self.settings.voiceOutputConfiguration,
            preferredLanguages: self.recordingSpokenLanguages
          )
          if !cleaned.isEmpty {
            combined = ExperimentalSpeechSegments.append(cleaned, to: combined)
            revision += 1
            ExperimentalLiveTranscription.write(sessionToken: token,
                                                 revision: revision, text: combined)
            self.liveDictationStatus = "Live update " + String(revision) + " delivered"
            if revision == 1 {
              FeatureDiagnostics.record(.liveDictation, .firstUpdate,
                durationMs: Int((CFAbsoluteTimeGetCurrent() - liveStartedAt) * 1_000))
            }
          }
        }
        if firstChunk && revision == 0 {
          switch result {
          case .text, .noSpeech:
            FeatureDiagnostics.record(.liveDictation, .noSpeech, operationID: token)
          case .failed:
            FeatureDiagnostics.record(.liveDictation, .failed, operationID: token)
          }
        }
        // Diagnostic is duration only. No text or audio is logged.
        let decodeSeconds = CFAbsoluteTimeGetCurrent() - started
        if decodeSeconds > 1.5 {
          if !reportedSlow {
            reportedSlow = true
            FeatureDiagnostics.record(.liveDictation, .slow, durationMs: Int(decodeSeconds * 1_000))
          }
          self.liveDictationStatus = "Live recognition behind recording: "
            + String(format: "%.1fs decode", decodeSeconds)
        }
        DiagnosticLog.write("experimental live: audio chunk decoded in "
          + String(format: "%.1f", decodeSeconds) + "s")
      }
    }
  }

  func stopExperimentalLive() async {
    let task = self.experimentalLiveTask
    if task != nil { FeatureDiagnostics.record(.liveDictation, .stopped) }
    self.experimentalLiveTask = nil
    task?.cancel()
    await task?.value
    self.liveDictationStatus = "Stopped"
  }
}

