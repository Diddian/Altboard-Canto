
import os

final class AudioBufferAccumulator: Sendable {

  var samples: [Float] {
    self.buffer.withLock { Array($0) }
  }

  func append(_ newSamples: [Float]) {
    self.buffer.withLock { $0.append(contentsOf: newSamples) }
  }

  /// Fixed-size copy for live ASR; avoids copying a long recording.
  func chunk(from offset: Int, count: Int) -> [Float]? {
    guard offset >= 0, count > 0, count <= 16_000 * 20 else { return nil }
    return self.buffer.withLock { samples in
      guard offset <= samples.count, samples.count - offset >= count else { return nil }
      return Array(samples[offset..<(offset + count)])
    }
  }

  /// Consume one bounded meeting segment while the recorder keeps writing.
  func consume(count: Int) -> [Float]? {
    guard count > 0, count <= 16_000 * 20 else { return nil }
    return self.buffer.withLock { samples in
      guard samples.count >= count else { return nil }
      let result = Array(samples.prefix(count))
      samples.removeFirst(count)
      return result
    }
  }

  func consumeAll() -> [Float] {
    self.buffer.withLock { samples in
      let result = Array(samples)
      samples.removeAll(keepingCapacity: true)
      return result
    }
  }

  func reset() {
    self.buffer.withLock { $0.removeAll(keepingCapacity: true) }
  }

  private let buffer = OSAllocatedUnfairLock<ContiguousArray<Float>>(initialState: [])
}
