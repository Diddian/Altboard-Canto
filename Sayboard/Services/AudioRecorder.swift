import Accelerate
@preconcurrency import AVFoundation
import os

final class AudioRecorder: Sendable {

  struct RecordingResult: Sendable {
    let url: URL
    let duration: TimeInterval
    let waveformSamples: [Float]
    let writeFailed: Bool
  }

  var hasWriteFailure: Bool {
    self.state.withLock { $0?.writeFailed ?? false }
  }

  func startRecording(fileName: String, format: AVAudioFormat,
                      directory overrideDirectory: URL? = nil) -> URL? {
    guard let directory = overrideDirectory ?? HistoryStore.shared.audioDirectoryURL else { return nil }
    let fileURL = directory.appendingPathComponent(fileName)
    do {
      let file = try AVAudioFile(forWriting: fileURL, settings: format.settings)
      try FileManager.default.setAttributes(
        [.protectionKey: FileProtectionType.completeUnlessOpen],
        ofItemAtPath: fileURL.path,
      )
      self.state.withLock { $0 = MutableState(audioFile: file) }
      return fileURL
    } catch {
      return nil
    }
  }

  func appendBuffer(_ buffer: AVAudioPCMBuffer) {
    self.state.withLock { current in
      if let file = current?.audioFile, current?.writeFailed == false {
        do {
          try file.write(from: buffer)
        } catch {
          current?.writeFailed = true
        }
      }

      guard let channelData = buffer.floatChannelData else { return }
      let frameCount = Int(buffer.frameLength)
      guard frameCount > 0 else { return }

      var peak: Float = 0
      vDSP_maxmgv(channelData[0], 1, &peak, vDSP_Length(frameCount))
      current?.bufferPeaks.append(peak)
    }
  }

  func stopRecording() -> RecordingResult? {
    let snapshot = self.state.withLock { current -> MutableState? in
      let value = current
      current = nil
      return value
    }
    return self.result(from: snapshot)
  }

  /// Open the next part before exchanging writers. A failed open leaves the
  /// old writer active, and callbacks cannot land between stop and start.
  func rotateRecording(fileName: String, format: AVAudioFormat, directory: URL) throws -> RecordingResult? {
    let url = directory.appendingPathComponent(fileName)
    let file = try AVAudioFile(forWriting: url, settings: format.settings)
    try FileManager.default.setAttributes(
      [.protectionKey: FileProtectionType.completeUnlessOpen], ofItemAtPath: url.path
    )
    let snapshot = self.state.withLock { current -> MutableState? in
      let previous = current
      current = MutableState(audioFile: file)
      return previous
    }
    return self.result(from: snapshot)
  }

  private func result(from snapshot: MutableState?) -> RecordingResult? {
    guard let snapshot else { return nil }
    let duration = Double(snapshot.audioFile.length) / snapshot.audioFile.processingFormat.sampleRate
    let url = snapshot.audioFile.url
    let samples = snapshot.bufferPeaks.waveform(count: self.waveformSampleCount)
    return RecordingResult(
      url: url, duration: duration, waveformSamples: samples,
      writeFailed: snapshot.writeFailed
    )
  }

  private struct MutableState {
    let audioFile: AVAudioFile
    var bufferPeaks = AudioWaveformPeaks()
    var writeFailed = false
  }

  private let waveformSampleCount = 128

  private let state = OSAllocatedUnfairLock<MutableState?>(initialState: nil)

}

