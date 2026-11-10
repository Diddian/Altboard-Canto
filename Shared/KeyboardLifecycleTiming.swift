import Foundation

/// Export-only analysis of extension lifecycle events. No host text, touches or
/// identifiers are captured; phases are measured only within one controller session.
enum KeyboardLifecycleTiming {
  enum Stage: String, Sendable {
    case loadViewStarting, hostingMounted, willAppear, didAppear
    case renderCheckpoint, renderSuspicious, willDisappear
  }

  struct Signal: Sendable {
    let session: String
    let timestampMs: Int64
    let stage: Stage

    init(_ timestampMs: Int64, _ stage: Stage, session: String) {
      self.timestampMs = timestampMs
      self.stage = stage
      self.session = session
    }
  }

  struct Appearance: Sendable {
    let session: String
    let startedAtMs: Int64
    let didAppearDelayMs: Int64?
    let checkpointDelayMs: Int64?
    let suspiciousRender: Bool
  }

  struct Summary: Sendable {
    let appearanceCount: Int
    let didAppearCount: Int
    let checkpointCount: Int
    let suspiciousAppearanceCount: Int
    let coldMountCount: Int
    let p95ColdLoadToMountMs: Int64?
    let p95AppearanceToCheckpointMs: Int64?
    let recentAppearances: [Appearance]
  }

  private struct PendingAppearance {
    let session: String
    let startedAtMs: Int64
    var didAppearDelayMs: Int64?
    var checkpointDelayMs: Int64?
    var suspiciousRender = false
  }

  private static let maximumPhaseMs: Int64 = 60_000

  static func analyze(_ signals: [Signal]) -> Summary {
    let ordered = signals.enumerated().sorted {
      if $0.element.timestampMs != $1.element.timestampMs {
        return $0.element.timestampMs < $1.element.timestampMs
      }
      return $0.offset < $1.offset
    }.map(\.element)

    var loadStarts = [String: Int64]()
    var mountedSessions = Set<String>()
    var mountDelays = [Int64]()
    var appearances = [PendingAppearance]()
    var activeAppearances = [String: Int]()

    for signal in ordered {
      guard !signal.session.isEmpty, signal.timestampMs >= 0 else { continue }
      switch signal.stage {
      case .loadViewStarting:
        loadStarts[signal.session] = signal.timestampMs
      case .hostingMounted:
        guard !mountedSessions.contains(signal.session),
              let start = loadStarts[signal.session],
              let delay = boundedDelay(from: start, to: signal.timestampMs)
        else { continue }
        mountedSessions.insert(signal.session)
        mountDelays.append(delay)
      case .willAppear:
        appearances.append(PendingAppearance(
          session: signal.session, startedAtMs: signal.timestampMs
        ))
        activeAppearances[signal.session] = appearances.count - 1
      case .didAppear, .renderCheckpoint, .renderSuspicious:
        guard let index = activeAppearances[signal.session],
              let delay = boundedDelay(
                from: appearances[index].startedAtMs, to: signal.timestampMs
              ) else { continue }
        switch signal.stage {
        case .didAppear:
          if appearances[index].didAppearDelayMs == nil {
            appearances[index].didAppearDelayMs = delay
          }
        case .renderCheckpoint:
          if appearances[index].checkpointDelayMs == nil {
            appearances[index].checkpointDelayMs = delay
          }
        case .renderSuspicious:
          appearances[index].suspiciousRender = true
        default: break
        }
      case .willDisappear:
        activeAppearances.removeValue(forKey: signal.session)
      }
    }
    return Summary(
      appearanceCount: appearances.count,
      didAppearCount: appearances.filter { $0.didAppearDelayMs != nil }.count,
      checkpointCount: appearances.filter { $0.checkpointDelayMs != nil }.count,
      suspiciousAppearanceCount: appearances.filter(\.suspiciousRender).count,
      coldMountCount: mountDelays.count,
      p95ColdLoadToMountMs: percentile95(mountDelays),
      p95AppearanceToCheckpointMs: percentile95(
        appearances.compactMap(\.checkpointDelayMs)
      ),
      recentAppearances: appearances.suffix(24).map {
        Appearance(
          session: $0.session, startedAtMs: $0.startedAtMs,
          didAppearDelayMs: $0.didAppearDelayMs,
          checkpointDelayMs: $0.checkpointDelayMs,
          suspiciousRender: $0.suspiciousRender
        )
      }
    )
  }

  private static func boundedDelay(from start: Int64, to end: Int64) -> Int64? {
    guard end >= start, start >= 0 else { return nil }
    let (delta, overflow) = end.subtractingReportingOverflow(start)
    guard !overflow, delta <= maximumPhaseMs else { return nil }
    return delta
  }

  private static func percentile95(_ numbers: [Int64]) -> Int64? {
    guard !numbers.isEmpty else { return nil }
    let sorted = numbers.sorted()
    let rank = (sorted.count * 95 + 99) / 100
    return sorted[max(0, rank - 1)]
  }
}
