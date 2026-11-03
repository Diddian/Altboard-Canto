import Foundation

/// Aggregate local-only diagnostics. No raw path, key sequence or host text.
struct SwipeTouchMetrics: Codable, Sendable {
  var gestures = 0
  var matchedGestures = 0
  var unmatchedGestures = 0
  var cancelledGestures = 0
  var emittedTrailFrames = 0
  var lastPointCount = 0
  var lastMatchCount = 0
  var lastReason = "none"
  var adjacentCorrections = 0
}

enum KeyboardExperimentMetrics {
  static let metricsKey = "canto.keyboard.swipeTouchMetrics.v1"
  static let calibrationKey = "canto.keyboard.touchCalibrationCounts.v1"

  static func read(defaults: UserDefaults? = AppGroup.sharedDefaults) -> SwipeTouchMetrics {
    guard let data = defaults?.data(forKey: metricsKey),
          let saved = try? JSONDecoder().decode(SwipeTouchMetrics.self, from: data)
    else { return SwipeTouchMetrics() }
    return saved
  }

  static func update(_ mutate: (inout SwipeTouchMetrics) -> Void,
                     defaults: UserDefaults? = AppGroup.sharedDefaults) {
    guard let defaults else { return }
    var metrics = read(defaults: defaults)
    mutate(&metrics)
    if let data = try? JSONEncoder().encode(metrics) {
      defaults.set(data, forKey: metricsKey)
    }
  }

  static func recordGesture(points: Int, trailUpdates: Int, matches: Int, reason: String,
                            defaults: UserDefaults? = AppGroup.sharedDefaults) {
    guard defaults?.bool(forKey: SharedKey.keyboardSwipeDiagnosticsEnabled) == true else { return }
    let allowed = ["matched", "no-candidate", "tap-or-short", "cancelled"]
    update({ metrics in
      metrics.gestures += 1
      metrics.matchedGestures += matches > 0 ? 1 : 0
      metrics.unmatchedGestures += matches == 0 && reason != "cancelled" ? 1 : 0
      metrics.cancelledGestures += reason == "cancelled" ? 1 : 0
      metrics.emittedTrailFrames += max(0, trailUpdates)
      metrics.lastPointCount = max(0, min(384, points))
      metrics.lastMatchCount = max(0, min(3, matches))
      metrics.lastReason = allowed.contains(reason) ? reason : "unknown"
    }, defaults: defaults)
  }

  /// Signed evidence per internal horizontal boundary. The first four
  /// explicit corrections do not change geometry, and movement grows slowly.
  static func calibration(row: Int, keyCount: Int,
                          defaults: UserDefaults? = AppGroup.sharedDefaults) -> [Double] {
    guard keyCount >= 2, (0...2).contains(row) else { return [] }
    let observed = defaults?.dictionary(forKey: calibrationKey)?[String(row)] as? [Int] ?? []
    return (0..<(keyCount - 1)).map { index in
      let count = index < observed.count ? max(-30, min(30, observed[index])) : 0
      guard abs(count) >= 5 else { return 0 }
      let magnitude = min(0.12, Double(abs(count) - 4) * 0.12 / 20)
      return count < 0 ? -magnitude : magnitude
    }
  }

  static func observeAdjacentCorrection(row: Int, wrong: Int, corrected: Int,
                                        keyCount: Int,
                                        defaults: UserDefaults? = AppGroup.sharedDefaults) {
    guard let defaults, (0...2).contains(row), keyCount >= 2,
          wrong >= 0, corrected >= 0, wrong < keyCount,
          corrected < keyCount, abs(wrong - corrected) == 1
    else { return }
    let boundary = min(wrong, corrected)
    var all = defaults.dictionary(forKey: calibrationKey) ?? [:]
    var evidence = all[String(row)] as? [Int] ?? []
    if evidence.count != keyCount - 1 {
      evidence = Array(repeating: 0, count: keyCount - 1)
    }
    // A right-hand correction needs the right key's left boundary shifted left.
    let direction = corrected > wrong ? -1 : 1
    evidence[boundary] = max(-30, min(30, evidence[boundary] + direction))
    all[String(row)] = evidence
    defaults.set(all, forKey: calibrationKey)
    update({ $0.adjacentCorrections += 1 }, defaults: defaults)
  }

  static func reset(defaults: UserDefaults? = AppGroup.sharedDefaults) {
    defaults?.removeObject(forKey: calibrationKey)
    defaults?.removeObject(forKey: metricsKey)
  }
}
