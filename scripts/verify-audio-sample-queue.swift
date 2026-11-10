import Foundation

@main
struct AudioSampleQueueSmoke {
  static func main() {
    var queue = AudioSampleQueue()
    precondition(queue.snapshot().isEmpty)
    precondition(queue.chunk(from: 0, count: 1) == nil)
    precondition(queue.consume(count: 1) == nil)

    queue.append([1, 2, 3, 4])
    precondition(queue.chunk(from: 1, count: 2) == [2, 3])
    precondition(queue.chunk(from: -1, count: 1) == nil)
    precondition(queue.chunk(from: 4, count: 1) == nil)
    precondition(queue.consume(count: 2) == [1, 2])
    queue.append([5, 6])
    precondition(queue.snapshot() == [3, 4, 5, 6])
    precondition(queue.consumeAll() == [3, 4, 5, 6])
    precondition(queue.snapshot().isEmpty)

    // Compare the optimized buffer against an independent reference FIFO.
    var reference = [Float]()
    for iteration in 0..<800 {
      let incoming = [Float](repeating: Float(iteration % 13), count: 512)
      queue.append(incoming)
      reference.append(contentsOf: incoming)
      if iteration % 4 != 0 {
        let remove = min(256, reference.count)
        precondition(queue.consume(count: remove) == Array(reference.prefix(remove)))
        reference.removeFirst(remove)
      }
      if iteration % 41 == 0 {
        let offset = reference.count / 3
        let length = min(reference.count - offset, 32)
        if length > 0 {
          precondition(queue.chunk(from: offset, count: length) == Array(reference[offset..<(offset + length)]))
        }
      }
    }
    precondition(queue.snapshot() == reference)
    precondition(queue.consumeAll() == reference)
    queue.append([7, 8])
    queue.reset()
    precondition(queue.count == 0)
    precondition(queue.snapshot().isEmpty)

    var bounded = AudioSampleQueue(maximumUnreadSamples: 4)
    bounded.append([1, 2, 3])
    bounded.append([4, 5, 6])
    precondition(bounded.snapshot() == [1, 2, 3, 4])
    precondition(bounded.droppedSamples == 2)
    precondition(bounded.consume(count: 3) == [1, 2, 3])
    bounded.append([7, 8, 9])
    precondition(bounded.snapshot() == [4, 7, 8, 9])
    precondition(bounded.droppedSamples == 2)
    precondition(bounded.consume(count: 4) == [4, 7, 8, 9])
    bounded.append([10])
    precondition(bounded.snapshot() == [10])
    precondition(bounded.droppedSamples == 2)
    bounded.reset()
    precondition(bounded.count == 0 && bounded.droppedSamples == 0)
    print("AudioSampleQueue: FIFO, bounds, compaction, cap, overflow, reset PASS")
  }
}
