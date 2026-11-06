import Foundation

/// Correlates host-field observations and extension events without claiming
/// that an input-mode language identifies the keyboard on screen.
enum KeyboardHandoffAnalyzer {
  static let observationWindowMs: Int64 = 4_000

  enum Kind: String {
    case hostMis, hostOther, fieldEnded
    case extensionStarting, extensionMounted, extensionAppearing, extensionRendered
  }
  enum Outcome: String {
    case extensionDetectedFieldUnconfirmed
    case modeChangedAwayBeforeLoad, launchNotObserved, awaitingEvidence
  }
  enum ExtensionStage: String {
    case started, appeared, mounted
  }
  struct Signal {
    let timestampMs: Int64
    let kind: Kind
    let remembersSelection: Bool?
    let activationID: String?
    let sessionID: String?

    init(
      _ timestampMs: Int64, _ kind: Kind,
      remembersSelection: Bool? = nil,
      activationID: String? = nil,
      sessionID: String? = nil
    ) {
      self.timestampMs = timestampMs
      self.kind = kind
      self.remembersSelection = remembersSelection
      self.activationID = activationID
      self.sessionID = sessionID
    }
  }
  struct Attempt {
    let timestampMs: Int64
    let activationID: String
    let remembersSelection: Bool
    let outcome: Outcome
    let extensionStage: ExtensionStage?
    let extensionSessionID: String?
    let loadDelayMs: Int64?
    let mountDelayMs: Int64?
    let changeAwayDelayMs: Int64?
    let focusEndedAfterMs: Int64?
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
      guard let activationID = signal.activationID else { continue }
      // Editing began and input-mode changed can report the same selection.
      if let prior = selections.last,
         prior.activationID == activationID,
         signal.timestampMs - prior.timestampMs < 350 { continue }
      selections.append(signal)
    }

    return selections.suffix(24).map { selection in
      let start = selection.timestampMs
      let activationID = selection.activationID!
      let deadline = start + observationWindowMs
      let focusEnd = ordered.first { signal in
        guard signal.timestampMs > start, signal.timestampMs <= deadline else { return false }
        if signal.kind == .fieldEnded && signal.activationID == activationID {
          return true
        }
        // A new test field ends the previous field's observation window.
        return (signal.kind == .hostMis || signal.kind == .hostOther)
          && signal.activationID != nil && signal.activationID != activationID
      }
      let modeAway = ordered.first { signal in
        signal.kind == .hostOther && signal.activationID == activationID
          && signal.timestampMs > start && signal.timestampMs <= deadline
      }
      let end = min(deadline, focusEnd?.timestampMs ?? deadline,
                    modeAway?.timestampMs ?? deadline)
      // Do not borrow earlier callbacks or later events from another field.
      let evidence = ordered.filter { signal in
        signal.timestampMs >= start && signal.timestampMs < end
          && signal.activationID == nil
      }
      let load = evidence.first { $0.kind == .extensionStarting }
      let mounted = evidence.first { $0.kind == .extensionMounted }
      let appeared = evidence.first {
        $0.kind == .extensionAppearing || $0.kind == .extensionRendered
      }
      let stage: ExtensionStage?
      let observed: Signal?
      if let mounted { stage = .mounted; observed = mounted }
      else if let appeared { stage = .appeared; observed = appeared }
      else if let load { stage = .started; observed = load }
      else { stage = nil; observed = nil }

      let outcome: Outcome
      if observed != nil { outcome = .extensionDetectedFieldUnconfirmed }
      else if modeAway != nil && (focusEnd == nil || modeAway!.timestampMs <= focusEnd!.timestampMs) {
        outcome = .modeChangedAwayBeforeLoad
      } else if nowMs >= end || focusEnd != nil {
        outcome = .launchNotObserved
      } else { outcome = .awaitingEvidence }

      return Attempt(
        timestampMs: start,
        activationID: activationID,
        remembersSelection: selection.remembersSelection ?? false,
        outcome: outcome,
        extensionStage: stage,
        extensionSessionID: observed?.sessionID,
        loadDelayMs: load.map { $0.timestampMs - start },
        mountDelayMs: mounted.map { $0.timestampMs - start },
        changeAwayDelayMs: modeAway.map { $0.timestampMs - start },
        focusEndedAfterMs: focusEnd.map { $0.timestampMs - start }
      )
    }
  }
}
