import Foundation

/// Time correlation for Altboard-owned test fields. A language tag does not
/// identify the active keyboard or establish why iOS changed input modes.
enum KeyboardHandoffAnalyzer {
  static let observationWindowMs: Int64 = 4_000
  private static let lookbackMs: Int64 = 350

  enum Kind: String {
    case hostMis, hostOther, extensionStarting, extensionMounted
    case extensionAppearing, extensionRendered
  }
  enum Outcome: String {
    case mountedObserved, appearanceObserved, loadStartedOnly
    case modeChangedAwayBeforeLoad, launchNotObserved, awaitingEvidence
  }
  struct Signal {
    let timestampMs: Int64
    let kind: Kind
    let remembersSelection: Bool?
    init(_ timestampMs: Int64, _ kind: Kind, remembersSelection: Bool? = nil) {
      self.timestampMs = timestampMs
      self.kind = kind
      self.remembersSelection = remembersSelection
    }
  }
  struct Attempt {
    let timestampMs: Int64
    let remembersSelection: Bool
    let outcome: Outcome
    let loadDelayMs: Int64?
    let mountDelayMs: Int64?
    let changeAwayDelayMs: Int64?
  }

  static func analyze(_ signals: [Signal], nowMs: Int64) -> [Attempt] {
    let ordered = signals.enumerated().sorted {
      if $0.element.timestampMs != $1.element.timestampMs {
        return $0.element.timestampMs < $1.element.timestampMs
      }
      return $0.offset < $1.offset
    }.map(\.element)

    var selections = [Signal]()
    for signal in ordered where signal.kind == .hostMis {
      if let prior = selections.last,
         prior.remembersSelection == signal.remembersSelection,
         signal.timestampMs - prior.timestampMs < 350 {
        continue
      }
      selections.append(signal)
    }

    return selections.suffix(24).map { selection in
      let start = selection.timestampMs
      let end = start + observationWindowMs
      let away = ordered.first { signal in
        signal.kind == .hostOther
          && signal.remembersSelection == selection.remembersSelection
          && signal.timestampMs > start && signal.timestampMs <= end
      }
      let evidenceEnd = min(end, away?.timestampMs ?? end)
      let evidence = ordered.filter { signal in
        signal.timestampMs >= start - lookbackMs && signal.timestampMs <= evidenceEnd
      }
      let load = evidence.first { $0.kind == .extensionStarting }
      let mount = evidence.first { $0.kind == .extensionMounted }
      let appear = evidence.first {
        $0.kind == .extensionAppearing || $0.kind == .extensionRendered
      }
      let outcome: Outcome
      if mount != nil { outcome = .mountedObserved }
      else if appear != nil { outcome = .appearanceObserved }
      else if load != nil { outcome = .loadStartedOnly }
      else if away != nil { outcome = .modeChangedAwayBeforeLoad }
      else if nowMs >= end { outcome = .launchNotObserved }
      else { outcome = .awaitingEvidence }

      return Attempt(
        timestampMs: start, remembersSelection: selection.remembersSelection ?? false,
        outcome: outcome, loadDelayMs: load.map { $0.timestampMs - start },
        mountDelayMs: mount.map { $0.timestampMs - start },
        changeAwayDelayMs: away.map { $0.timestampMs - start }
      )
    }
  }
}
