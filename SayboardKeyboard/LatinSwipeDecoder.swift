import Foundation

/// Keyboard-local logical points; paths are transient and never persisted.
struct LatinSwipePoint: Equatable, Sendable {
  let x: Double
  let y: Double

  func distance(to other: Self) -> Double {
    hypot(self.x - other.x, self.y - other.y)
  }
}

/// Offline geometric prototype. This deliberately makes no claim to Apple
/// QuickPath's private language model or prediction algorithm.
enum LatinSwipeDecoder {
  static let sampleCount = 32

  static func centers(
    arrangement: LetterKeyArrangement, fullWidth: Double
  ) -> [String: LatinSwipePoint] {
    guard fullWidth > 200 else { return [:] }
    let rows = arrangement.rows
    let insets = [3.67, 25.0, 0.0]
    let origins = [0.0, 0.0, 6.67 + 50.0 + 11.67]
    let widths = [
      fullWidth, fullWidth,
      fullWidth - (2 * 6.67 + 2 * 50.0 + 2 * 11.67)
    ]
    let y = [22.5, 78.5, 134.5]
    var result = [String: LatinSwipePoint]()
    for row in 0..<3 {
      let letters = rows[row]
      let cell = (widths[row] - 2 * insets[row]) / Double(letters.count)
      for (col, letter) in letters.enumerated() {
        result[letter.lowercased()] = LatinSwipePoint(
          x: origins[row] + insets[row] + cell * (Double(col) + 0.5),
          y: y[row]
        )
      }
    }
    return result
  }

  static func nearestLetter(
    to point: LatinSwipePoint,
    arrangement: LetterKeyArrangement,
    fullWidth: Double
  ) -> String? {
    centers(arrangement: arrangement, fullWidth: fullWidth)
      .min { $0.value.distance(to: point) < $1.value.distance(to: point) }?.key
  }

  /// Arc-length sample points uniformly, not by frame rate or touch speed.
  static func resample(_ points: [LatinSwipePoint], count: Int = sampleCount)
    -> [LatinSwipePoint] {
    guard let first = points.first, count > 1 else { return points }
    var distance = [0.0]
    for i in 1..<points.count {
      distance.append(distance[i-1] + points[i-1].distance(to: points[i]))
    }
    let total = distance.last ?? 0
    guard total > 0 else { return Array(repeating: first, count: count) }
    var sampled = [LatinSwipePoint]()
    var position = 1
    for i in 0..<count {
      let target = total * Double(i) / Double(count - 1)
      while position < distance.count - 1 && distance[position] < target {
        position += 1
      }
      let lower = position - 1
      let upper = position
      let section = max(0.00001, distance[upper] - distance[lower])
      let fraction = min(1, max(0, (target - distance[lower]) / section))
      let a = points[lower], b = points[upper]
      sampled.append(LatinSwipePoint(
        x: a.x + (b.x - a.x) * fraction,
        y: a.y + (b.y - a.y) * fraction
      ))
    }
    return sampled
  }

  static func gestureLength(_ points: [LatinSwipePoint]) -> Double {
    guard points.count > 1 else { return 0 }
    return zip(points, points.dropFirst()).reduce(0) {
      $0 + $1.0.distance(to: $1.1)
    }
  }

  static func normalizedSpelling(_ word: String) -> String {
    word.lowercased()
      .replacingOccurrences(of: "ä", with: "a")
      .replacingOccurrences(of: "ö", with: "o")
      .replacingOccurrences(of: "ü", with: "u")
      .replacingOccurrences(of: "ß", with: "ss")
      .filter { $0.isASCII && $0.isLetter }
  }

  static func rank(
    path: [LatinSwipePoint], arrangement: LetterKeyArrangement,
    fullWidth: Double, words: [String], limit: Int = 3
  ) -> [String] {
    guard path.count >= 3, gestureLength(path) >= 65, limit > 0 else { return [] }
    let centers = centers(arrangement: arrangement, fullWidth: fullWidth)
    guard let first = path.first, let last = path.last else { return [] }
    let sampled = resample(path)
    let measuredLength = gestureLength(path)
    var ranked = [(word: String, score: Double)]()
    var seen = Set<String>()
    for (frequencyOrder, raw) in words.enumerated() {
      let normalized = normalizedSpelling(raw)
      guard (2...32).contains(normalized.count), seen.insert(normalized).inserted,
            let firstChar = normalized.first,
            let lastChar = normalized.last,
            let a = centers[String(firstChar)],
            let z = centers[String(lastChar)],
            first.distance(to: a) <= 68,
            last.distance(to: z) <= 68
      else { continue }
      var template = [LatinSwipePoint]()
      for letter in normalized {
        guard let point = centers[String(letter)] else { continue }
        if template.last != point { template.append(point) }
      }
      guard template.count >= 2 else { continue }
      let templateLength = gestureLength(template)
      let reference = resample(template)
      guard reference.count == sampled.count else { continue }
      let locationCost = zip(sampled, reference).reduce(0.0) {
        $0 + $1.0.distance(to: $1.1)
      } / Double(sampled.count)
      let lengthPenalty = abs(measuredLength - templateLength) * 0.18
      let endpointPenalty = 0.2 * (first.distance(to: a) + last.distance(to: z))
      // Corpus order is a small frequency prior, never stronger than geometry.
      let prior = log1p(Double(frequencyOrder)) * 0.25
      let score = locationCost + lengthPenalty + endpointPenalty + prior
      if score < 68 { ranked.append((raw, score)) }
    }
    return ranked.sorted { $0.score < $1.score }
      .prefix(limit).map(\.word)
  }
}

/// One retained gesture, including moves beyond the row where it began.
final class LatinSwipeSession {
  private(set) var points = [LatinSwipePoint]()
  private(set) var visited = Set<String>()

  func begin(_ point: LatinSwipePoint, arrangement: LetterKeyArrangement, width: Double) {
    points = []
    visited = []
    append(point, arrangement: arrangement, width: width)
  }

  func append(_ point: LatinSwipePoint, arrangement: LetterKeyArrangement, width: Double) {
    guard points.count < 160 else { return }
    if let previous = points.last, previous.distance(to: point) < 4 { return }
    points.append(point)
    if let key = LatinSwipeDecoder.nearestLetter(
      to: point, arrangement: arrangement, fullWidth: width
    ) {
      visited.insert(key)
    }
  }

  var isLikelyGlide: Bool {
    visited.count >= 3 && LatinSwipeDecoder.gestureLength(points) >= 78
  }

  func reset() {
    points.removeAll(keepingCapacity: true)
    visited.removeAll(keepingCapacity: true)
  }
}
