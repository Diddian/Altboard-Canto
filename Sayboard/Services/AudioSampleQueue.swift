import Foundation

/// FIFO of 16 kHz mono samples. Consumed audio is compacted in batches so a
/// long meeting does not repeatedly shift the entire pending audio buffer.
struct AudioSampleQueue: Sendable {
  private var storage: ContiguousArray<Float> = []
  private var readIndex = 0
  private static let compactThreshold = 16_000 * 5
  private static let maximumRetainedCapacity = 16_000 * 60

  var count: Int { storage.count - readIndex }

  mutating func append(_ samples: [Float]) {
    guard !samples.isEmpty else { return }
    compactIfNeeded()
    storage.append(contentsOf: samples)
  }

  func snapshot() -> [Float] {
    Array(storage[readIndex...])
  }

  func chunk(from offset: Int, count requested: Int) -> [Float]? {
    guard offset >= 0, requested > 0,
          offset <= count, requested <= count - offset else { return nil }
    let start = readIndex + offset
    return Array(storage[start..<(start + requested)])
  }

  mutating func consume(count requested: Int) -> [Float]? {
    guard let result = chunk(from: 0, count: requested) else { return nil }
    readIndex += requested
    compactIfNeeded()
    return result
  }

  mutating func consumeAll() -> [Float] {
    let result = snapshot()
    reset()
    return result
  }

  mutating func reset() {
    if storage.capacity > Self.maximumRetainedCapacity {
      storage = []
    } else {
      storage.removeAll(keepingCapacity: true)
    }
    readIndex = 0
  }

  private mutating func compactIfNeeded() {
    guard readIndex > 0 else { return }
    if readIndex == storage.count {
      reset()
    } else if readIndex >= Self.compactThreshold && readIndex >= storage.count / 2 {
      storage.removeFirst(readIndex)
      readIndex = 0
    }
  }
}
