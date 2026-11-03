import Foundation

extension SpeechRecognitionService {
  /// Called after capture has started. This uses the existing microphone tap.
  func startExperimentalLiveIfNeeded() {
    guard self.settings.experimentalLiveDictationEnabled,
          self.settings.selectedVariant.engine == .qwen3,
          let token = self.settings.dictationSessionToken,
          !token.isEmpty, self.experimentalLiveTask == nil else { return }
    self.liveDictationStatus = "Waiting for 3 seconds of audio and Qwen model"
    self.experimentalLiveTask = Task { @MainActor [weak self] in
      guard let self else { return }
      var readOffset = 0
      var revision = 0
      var combined = ""
      let frameCount = 3 * 16_000
      while !Task.isCancelled && self.isRecording {
        guard self.activeLoadState == .loaded,
              let samples = self.accumulator.chunk(from: readOffset, count: frameCount)
        else {
          try? await Task.sleep(for: .milliseconds(350))
          continue
        }
        readOffset += samples.count
        self.liveDictationStatus = "Transcribing live segment"
        let started = CFAbsoluteTimeGetCurrent()
        let result = await self.qwen3Service.transcribe(audioSamples: samples)
        guard !Task.isCancelled, self.isRecording else { break }
        if case .text(let output) = result {
          combined = ExperimentalSpeechSegments.append(output.text, to: combined)
          revision += 1
          ExperimentalLiveTranscription.write(sessionToken: token,
                                               revision: revision, text: combined)
          self.liveDictationStatus = "Live update " + String(revision) + " delivered"
        }
        // Diagnostic is duration only. No text or audio is logged.
        DiagnosticLog.write("experimental live: 3s decode completed in \(String(format: "%.1f", CFAbsoluteTimeGetCurrent() - started))s")
      }
    }
  }

  func stopExperimentalLive() async {
    let task = self.experimentalLiveTask
    self.experimentalLiveTask = nil
    task?.cancel()
    await task?.value
    self.liveDictationStatus = "Stopped"
  }
}
