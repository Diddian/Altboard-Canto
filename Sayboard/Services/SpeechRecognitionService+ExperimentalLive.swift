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
      var firstCompleted = false
      var firstReadyRecorded = false
      var modelReadyRecorded = false
      var firstWindow = self.settings.liveFirstWindowSamples

      while !Task.isCancelled && self.isRecording {
        if self.activeLoadState == .loaded && !modelReadyRecorded {
          modelReadyRecorded = true
          LiveDictationLatency.mark(.modelReady, token: token)
        }
        // If the model cold-loaded after 1.5 s of speech accumulated, skip
        // redundant 0.2/0.5/1 s decodes of old audio; they cannot catch up.
        if !firstCompleted && firstWindow < LiveDictationChunkPolicy.firstQwenSamples
            && self.accumulator.sampleCount - readOffset
                >= LiveDictationChunkPolicy.firstQwenSamples {
          firstWindow = LiveDictationChunkPolicy.firstQwenSamples
          FeatureDiagnostics.record(.liveDictation, .fallback, operationID: token)
        }
        let frameCount = LiveDictationChunkPolicy.samples(
          isQwen: true, hasAttemptedFirst: firstCompleted,
          firstWindowSamples: firstWindow
        )
        guard self.activeLoadState == .loaded,
              let samples = self.accumulator.chunk(from: readOffset, count: frameCount)
        else {
          do { try await Task.sleep(for: .milliseconds(firstCompleted ? 120 : 60)) }
          catch { break }
          continue
        }
        let firstChunk = !firstCompleted
        if firstChunk && !firstReadyRecorded {
          firstReadyRecorded = true
          LiveDictationLatency.mark(.firstChunkReady, token: token)
          FeatureDiagnostics.record(.liveDictation, .firstChunkReady,
            durationMs: Int((CFAbsoluteTimeGetCurrent() - liveStartedAt) * 1_000),
            operationID: token)
        }
        self.liveDictationStatus = "Transcribing live segment"
        let started = CFAbsoluteTimeGetCurrent()
        let result = await self.transcribeSamples(samples)
        guard !Task.isCancelled, self.isRecording else { break }

        var published = false
        if case .text(let output) = result {
          let cleaned = CantoneseOutput.normalizeDictation(
            TextSanitizer.sanitize(output.text),
            options: self.settings.voiceOutputConfiguration,
            preferredLanguages: self.recordingSpokenLanguages
          )
          if !cleaned.isEmpty {
            if revision == 0 { LiveDictationLatency.mark(.firstDecoded, token: token) }
            let updated = ExperimentalSpeechSegments.append(cleaned, to: combined)
            if ExperimentalLiveTranscription.write(
              sessionToken: token, revision: revision + 1, text: updated
            ) {
              combined = updated
              revision += 1
              published = true
              self.liveDictationStatus = "Live update " + String(revision) + " delivered"
              if revision == 1 {
                LiveDictationLatency.mark(.firstPublished, token: token)
                FeatureDiagnostics.record(.liveDictation, .firstUpdate,
                  durationMs: Int((CFAbsoluteTimeGetCurrent() - liveStartedAt) * 1_000),
                  operationID: token)
              }
            } else {
              FeatureDiagnostics.record(.liveDictation, .failed, operationID: token)
            }
          }
        }
        // A short first sample might have no words. Retry progressively
        // with the SAME initial audio, never discarding the first syllables.
        if firstChunk && !published,
           let next = LiveDictationChunkPolicy.retryFirstWindow(after: firstWindow) {
          firstWindow = next
          FeatureDiagnostics.record(.liveDictation, .noSpeech, operationID: token)
        } else {
          readOffset += samples.count
          firstCompleted = true
          if firstChunk && !published {
            switch result {
            case .text, .noSpeech: FeatureDiagnostics.record(.liveDictation, .noSpeech, operationID: token)
            case .failed: FeatureDiagnostics.record(.liveDictation, .failed, operationID: token)
            }
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

