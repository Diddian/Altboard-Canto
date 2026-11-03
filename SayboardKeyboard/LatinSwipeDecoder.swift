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
  static let sampleCount = 40

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

  /// Banded elastic alignment permits long words, turns and self-crossings.
  /// The first cheap pass limits work before running DTW on 48 finalists.
  private static func warpedDistance(_ a: [LatinSwipePoint],
                                     _ b: [LatinSwipePoint]) -> Double {
    guard a.count == b.count, !a.isEmpty else { return .infinity }
    let size = a.count
    let band = max(6, size / 5)
    var previous = [Double](repeating: .infinity, count: size + 1)
    previous[0] = 0
    for i in 1...size {
      var current = [Double](repeating: .infinity, count: size + 1)
      for j in max(1, i - band)...min(size, i + band) {
        let cost = a[i - 1].distance(to: b[j - 1])
        current[j] = cost + min(previous[j - 1], previous[j], current[j - 1])
      }
      previous = current
    }
    return previous[size] / Double(size)
  }

  static func rank(
    path: [LatinSwipePoint], arrangement: LetterKeyArrangement,
    fullWidth: Double, words: [String], limit: Int = 3
  ) -> [String] {
    guard path.count >= 2, gestureLength(path) >= 45, limit > 0 else { return [] }
    let centers = centers(arrangement: arrangement, fullWidth: fullWidth)
    guard let first = path.first, let last = path.last else { return [] }
    let sampled = resample(path)
    let measuredLength = gestureLength(path)
    var shortlist = [(word: String, rough: Double, template: [LatinSwipePoint], short: Bool)]()
    var seen = Set<String>()
    for (frequencyOrder, raw) in words.enumerated() {
      let normalized = normalizedSpelling(raw)
      guard (2...32).contains(normalized.count), seen.insert(normalized).inserted,
            let firstChar = normalized.first, let lastChar = normalized.last,
            let a = centers[String(firstChar)], let z = centers[String(lastChar)],
            first.distance(to: a) <= 68, last.distance(to: z) <= 68
      else { continue }
      var template = [LatinSwipePoint]()
      for letter in normalized {
        guard let point = centers[String(letter)] else { continue }
        if template.last != point { template.append(point) }
      }
      guard template.count >= 2 else { continue }
      let templateLength = gestureLength(template)
      let normalizedLengthCost = abs(log((measuredLength + 30) / (templateLength + 30))) * 30
      let reference = resample(template)
      let location = zip(sampled, reference).reduce(0.0) {
        $0 + $1.0.distance(to: $1.1)
      } / Double(sampled.count)
      let endpoints = 0.2 * (first.distance(to: a) + last.distance(to: z))
      let prior = log1p(Double(frequencyOrder)) * 0.18
      let rough = location + normalizedLengthCost + endpoints + prior
      if rough < 105 {
        shortlist.append((word: raw, rough: rough, template: reference,
                          short: normalized.count == 2))
      }
    }
    let shortlisted = shortlist.sorted { $0.rough < $1.rough }.prefix(48)
    return Array(shortlisted.compactMap { candidate -> (String, Double)? in
      let elastic = warpedDistance(sampled, candidate.template)
      let score = candidate.rough * 0.42 + elastic * 0.58
      guard candidate.short ? score < 28 : score < 67 else { return nil }
      return (candidate.word, score)
    }.sorted { $0.1 < $1.1 }.prefix(limit).map(\.0))
  }

}

/// One retained gesture, including moves beyond the row where it began.
final class LatinSwipeSession {
  private(set) var points = [LatinSwipePoint]()
  private(set) var visited = Set<String>()
  private var cachedCenters = [String: LatinSwipePoint]()

  func begin(_ point: LatinSwipePoint, arrangement: LetterKeyArrangement, width: Double) {
    points = []
    visited = []
    cachedCenters = LatinSwipeDecoder.centers(
      arrangement: arrangement, fullWidth: width
    )
    append(point, arrangement: arrangement, width: width)
  }

  func append(_ point: LatinSwipePoint, arrangement: LetterKeyArrangement, width: Double) {
    guard points.count < 384 else { return }
    let previous = points.last
    if let previous, previous.distance(to: point) < 4 { return }
    // Fill sparse UIKit events so fast cross-row swipes still visit keys.
    let distance = previous?.distance(to: point) ?? 0
    let segments = max(1, Int(ceil(distance / 18)))
    for index in 1...segments {
      guard points.count < 384 else { break }
      let step = Double(index) / Double(segments)
      let next = previous.map {
        LatinSwipePoint(
          x: $0.x + (point.x - $0.x) * step,
          y: $0.y + (point.y - $0.y) * step
        )
      } ?? point
      points.append(next)
      if let key = cachedCenters.min(by: {
        $0.value.distance(to: next) < $1.value.distance(to: next)
      })?.key {
        visited.insert(key)
      }
    }
  }

  var isLikelyGlide: Bool {
    // Short two-letter swipes cannot visit three distinct letters reliably.
    // Require longer physical travel for two-key gestures than for a
    // conventional tap-to-neighbor correction.
    (visited.count >= 3 && LatinSwipeDecoder.gestureLength(points) >= 78)
      || (visited.count >= 2 && LatinSwipeDecoder.gestureLength(points) >= 70)
  }

  func reset() {
    points.removeAll(keepingCapacity: true)
    visited.removeAll(keepingCapacity: true)
    cachedCenters.removeAll(keepingCapacity: true)
  }
}
