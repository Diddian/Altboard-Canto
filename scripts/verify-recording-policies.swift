import Foundation

@main
struct RecordingPolicyChecks {
  static func main() {
    precondition(DictationRequestPolicy.isCurrent(started: "a", current: "a", cancelled: false))
    precondition(!DictationRequestPolicy.isCurrent(started: "a", current: "a", cancelled: true))
    precondition(!DictationRequestPolicy.isCurrent(started: "a", current: "b", cancelled: false))
    precondition(!DictationRequestPolicy.isCurrent(started: nil, current: nil, cancelled: false))
    precondition(!DictationRequestPolicy.isCurrent(started: "", current: "", cancelled: false))
    precondition(!DictationRequestPolicy.isCurrent(started: "a", current: nil, cancelled: false))

    var envelope = AudioWaveformPeaks()
    precondition(envelope.waveform(count: 3) == [1, 1, 1])
    precondition(envelope.waveform(count: 0).isEmpty)
    envelope.append(0.25)
    envelope.append(-0.75)
    envelope.append(.nan)
    envelope.append(.infinity)
    precondition(envelope.waveform(count: 128) == [0.75, 0.25])
    precondition(envelope.waveform(count: 1) == [0.25])

    // Long capture stays bounded and preserves isolated peaks through merging.
    var long = AudioWaveformPeaks()
    for index in 0..<500_003 {
      long.append(index == 100_001 ? 1 : 0)
      precondition(long.retainedCount <= AudioWaveformPeaks.maximumBins)
    }
    let waveform = long.waveform(count: 128)
    precondition(waveform.count == 128)
    precondition(waveform.min() == 0 && waveform.max() == 1)
    precondition(waveform.allSatisfy { $0.isFinite && (0...1).contains($0) })
    print("Recording policies: stale/cancelled requests and bounded waveform PASS")
  }
}
