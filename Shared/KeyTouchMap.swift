import Foundation

/// A contiguous hit map for an alphabetic key row. The visible key rectangles
/// stay unchanged; the first and last cells also absorb their row margins.
/// Inspired by JBoard's bounded boundary shifts, not Apple's private code.
enum KeyTouchMap {
  static let predictiveLimit = 0.12
  static let combinedLimit = 0.18
  static let visibleGap: Double = 6

  /// Every boundary is shared by two adjacent keys. Probability and learned
  /// calibration may move that boundary by at most 18% of a key cell.
  static func boundaries(
    width: Double, keyCount: Int, horizontalInset: Double,
    weights: [Double] = [], calibrations: [Double] = []
  ) -> [Double] {
    guard width.isFinite, width > 0, keyCount > 0 else { return [] }
    if keyCount == 1 { return [0, width] }
    let inset = min(max(0, horizontalInset), width * 0.35)
    let cell = (width - 2 * inset) / Double(keyCount)
    guard cell > 0 else { return [] }
    var result = [0.0]
    for i in 1..<keyCount {
      let midpoint = inset + Double(i) * cell
      let left = i - 1
      let right = i
      func validWeight(_ index: Int) -> Double {
        guard index < weights.count, weights[index].isFinite else { return 0 }
        return min(1, max(0, weights[index]))
      }
      let predictiveShift = cell * predictiveLimit * (validWeight(left) - validWeight(right))
      let learned = left < calibrations.count && calibrations[left].isFinite
        ? min(0.12, max(-0.12, calibrations[left])) * cell : 0
      let cap = cell * combinedLimit
      result.append(midpoint + min(cap, max(-cap, predictiveShift + learned)))
    }
    result.append(width)
    return result
  }

  static func keyIndex(
    at position: Double, width: Double, keyCount: Int, horizontalInset: Double,
    weights: [Double] = [], calibrations: [Double] = []
  ) -> Int? {
    guard position.isFinite, position >= 0, position <= width else { return nil }
    let edges = boundaries(
      width: width, keyCount: keyCount, horizontalInset: horizontalInset,
      weights: weights, calibrations: calibrations
    )
    guard edges.count == keyCount + 1 else { return nil }
    // A row contains no horizontal dead zones. Exact boundary taps resolve
    // consistently to the key on the right.
    var low = 0
    var high = keyCount
    while low < high {
      let mid = (low + high) / 2
      if position < edges[mid + 1] { high = mid } else { low = mid + 1 }
    }
    return min(low, keyCount - 1)
  }

  static func visibleKeyBounds(
    width: Double, keyCount: Int, horizontalInset: Double, index: Int
  ) -> ClosedRange<Double>? {
    guard width > 0, keyCount > 0, index >= 0, index < keyCount else { return nil }
    let inset = min(max(0, horizontalInset), width * 0.35)
    let cell = (width - 2 * inset) / Double(keyCount)
    let left = inset + Double(index) * cell + visibleGap / 2
    let right = inset + Double(index + 1) * cell - visibleGap / 2
    return left...max(left, right)
  }
}

/// Prefer only next letters that are actually supported by offline candidate
/// completions. No external calls and no prediction when evidence is missing.
enum KeyTouchPrediction {
  static func weights(
    typed: String?, completions: [String], row: [String]
  ) -> [Double] {
    guard let typed, !typed.isEmpty else { return Array(repeating: 0, count: row.count) }
    let prefix = typed.lowercased()
    var counts = [String: Double]()
    for word in completions.prefix(24) {
      let lower = word.lowercased().filter { $0.isLetter }
      guard lower.hasPrefix(prefix), lower.count > prefix.count else { continue }
      let position = lower.index(lower.startIndex, offsetBy: prefix.count)
      let next = String(lower[position])
      counts[next, default: 0] += 1
    }
    let peak = counts.values.max() ?? 0
    guard peak > 0 else { return Array(repeating: 0, count: row.count) }
    return row.map { min(1, (counts[$0.lowercased()] ?? 0) / peak) }
  }
}
