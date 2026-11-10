
import os

final class AudioBufferAccumulator: Sendable {

  var samples: [Float] {
    self.buffer.withLock { $0.snapshot() }
  }

  var sampleCount: Int {
    self.buffer.withLock { $0.count }
  }

  var droppedSampleCount: Int {
    self.buffer.withLock { $0.droppedSamples }
  }

  init(maximumUnreadSamples: Int? = nil) {
    self.buffer = OSAllocatedUnfairLock(
      initialState: AudioSampleQueue(maximumUnreadSamples: maximumUnreadSamples)
    )
  }

  func append(_ newSamples: [Float]) {
    self.buffer.withLock { $0.append(newSamples) }
  }

  /// Fixed-size copy for live ASR; avoids copying a long recording.
  func chunk(from offset: Int, count: Int) -> [Float]? {
    guard offset >= 0, count > 0, count <= 16_000 * 20 else { return nil }
    return self.buffer.withLock { $0.chunk(from: offset, count: count) }
  }

  /// Consume one bounded meeting segment while the recorder keeps writing.
  func consume(count: Int) -> [Float]? {
    guard count > 0, count <= 16_000 * 20 else { return nil }
    return self.buffer.withLock { $0.consume(count: count) }
  }

  func consumeAll() -> [Float] {
    self.buffer.withLock { $0.consumeAll() }
  }

  func reset() {
    self.buffer.withLock { $0.reset() }
  }

  private let buffer: OSAllocatedUnfairLock<AudioSampleQueue>
}
