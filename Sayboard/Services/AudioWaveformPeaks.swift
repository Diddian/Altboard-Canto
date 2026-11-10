/// Bounded peak envelope. Adjacent bins merge at capacity; audio is never stored.
struct AudioWaveformPeaks: Sendable {
  static let maximumBins = 4_096
  private var bins = [Float]()
  private var samplesPerBin = 1
  private var pendingCount = 0
  private var pendingPeak: Float = 0

  var retainedCount: Int { bins.count + (pendingCount > 0 ? 1 : 0) }

  mutating func append(_ value: Float) {
    guard value.isFinite else { return }
    if bins.count == Self.maximumBins {
      for index in 0..<(bins.count / 2) {
        bins[index] = max(bins[index * 2], bins[index * 2 + 1])
      }
      bins.removeLast(bins.count / 2)
      samplesPerBin *= 2
    }
    pendingPeak = max(pendingPeak, abs(value))
    pendingCount += 1
    if pendingCount == samplesPerBin {
      bins.append(pendingPeak)
      pendingCount = 0
      pendingPeak = 0
    }
  }

  func waveform(count: Int) -> [Float] {
    guard count > 0 else { return [] }
    var envelope = bins
    if pendingCount > 0 { envelope.append(pendingPeak) }
    guard !envelope.isEmpty else { return Array(repeating: 1, count: count) }
    guard envelope.count > count else { return envelope.map { 1 - min($0, 1) } }
    return (0..<count).map { index in
      let start = index * envelope.count / count
      let end = (index + 1) * envelope.count / count
      return 1 - min(envelope[start..<end].max() ?? 0, 1)
    }
  }
}
