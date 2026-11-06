import Foundation
#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#endif

/// Local, bounded lifecycle metadata. Never record host text, keystrokes,
/// cursor locations, raw host identifiers, audio, or touch paths.
enum KeyboardLifecycleTrace {
  enum Event: String, Sendable {
    case loadViewStarting
    case inputViewLoaded
    case hostingMounted
    case willAppear
    case didAppear
    case willDisappear
    case didDisappear
    case documentChanged
    case documentIdentifierUnavailable
    case documentIdentifierRecovered
    case inputModeChanged
    case hostTextCleared
    case layoutChanged
    case switchRequirementChanged
    case memoryWarning
    case memorySample
    case renderCheckpoint
    case renderSuspicious
    case renderRefreshRequested

    var needsImmediateWrite: Bool {
      switch self {
      case .loadViewStarting, .willAppear, .willDisappear, .didDisappear,
           .inputModeChanged, .hostTextCleared, .documentIdentifierUnavailable,
           .documentIdentifierRecovered,
           .memoryWarning, .renderSuspicious, .renderRefreshRequested: true
      default: false
      }
    }

    var samplesProcessMemory: Bool {
      switch self {
      case .inputViewLoaded, .hostingMounted, .willAppear, .didAppear,
           .willDisappear, .didDisappear, .documentChanged, .hostTextCleared,
           .documentIdentifierUnavailable, .documentIdentifierRecovered,
           .memoryWarning, .memorySample, .renderCheckpoint, .renderSuspicious,
           .renderRefreshRequested: true
      default: false
      }
    }
  }

  /// A snapshot of view geometry and hit testing, not a screenshot or input record.
  struct RenderProbe: Codable, Sendable {
    let checkpoint: String
    let inputWidth: Int
    let inputHeight: Int
    let hostingWidth: Int
    let hostingHeight: Int
    let geometryWidth: Int
    let geometryHeight: Int
    let inputAlphaPercent: Int
    let hostingAlphaPercent: Int
    let inputHidden: Bool
    let hostingHidden: Bool
    let hostingInWindow: Bool
    let hostingIntersectsInput: Bool
    let visitedSubviews: Int
    let scanLimited: Bool
    let hostingLayerCount: Int
    let touchSurfaceCount: Int
    let touchSurfacesInWindow: Int
    let touchHitTestCount: Int
    let letterRowsExpected: Bool
  }

  /// Document input mode is observable only while this extension is running.
  /// Available languages are installed modes, not the currently selected keyboard.
  struct InputModeProbe: Codable, Sendable {
    let documentModePresent: Bool
    let documentLanguage: String?
    let extensionLanguage: String?
    let availableLanguages: [String]
    let requestedKeyboardType: Int
  }

  private struct Entry: Codable, Sendable {
    let timestampMs: Int64
    let systemUptimeMs: Int64
    let processID: Int32
    let buildSHA: String
    let session: String
    let processLaunchID: String
    let event: String
    let requestedMode: String
    let effectiveMode: String
    let fallback: Bool
    let viewWidth: Int
    let viewHeight: Int
    let hostWidth: Int
    let hostHeight: Int
    let hostingMounted: Bool
    let hostingInWindow: Bool
    let nativeSwitchRequired: Bool
    let fullAccess: Bool
    let appGroupAvailable: Bool
    let hostHint: String
    let firstLoadForBuild: Bool?
    let inputModeProbe: InputModeProbe?
    let processMemory: KeyboardProcessMemory.Snapshot?
    let renderProbe: RenderProbe?
  }

  private static let buildSHA = Bundle.main.infoDictionary?["AltboardBuildSHA"] as? String ?? "unknown"
  private static let filename = "keyboard-lifecycle-v1.jsonl"
  private static let maxBytes: off_t = 1_048_576
  private static let queue = DispatchQueue(label: "app.sayboard.keyboard.lifecycle", qos: .utility)
  private static var fileURL: URL? { AppGroup.containerURL?.appendingPathComponent(filename) }

  // Recovery builds keep historical exports, but do not probe or write new traces.
  static var captureEnabled: Bool {
    #if ALTBOARD_DEVELOPMENT_TRACING && !APPSTORE
    true
    #else
    false
    #endif
  }

  static func record(
    _ event: Event, session: String, requestedMode: KeyboardKind,
    effectiveMode: KeyboardKind, viewWidth: CGFloat, viewHeight: CGFloat,
    hostWidth: CGFloat, hostHeight: CGFloat, hostingMounted: Bool,
    hostingInWindow: Bool, nativeSwitchRequired: Bool, fullAccess: Bool,
    hostBundleHint: String?, firstLoadForBuild: Bool? = nil,
    inputModeProbe: InputModeProbe? = nil, renderProbe: RenderProbe? = nil
  ) {
    #if ALTBOARD_DEVELOPMENT_TRACING && !APPSTORE
    let processMemory = event.samplesProcessMemory
      ? KeyboardProcessMemory.snapshot() : nil
    let entry = Entry(
      timestampMs: Int64(Date().timeIntervalSince1970 * 1_000),
      systemUptimeMs: Int64(ProcessInfo.processInfo.systemUptime * 1_000),
      processID: ProcessInfo.processInfo.processIdentifier,
      buildSHA: buildSHA,
      session: session, processLaunchID: KeyboardProcessMemory.processLaunchID,
      event: event.rawValue,
      requestedMode: requestedMode.rawValue, effectiveMode: effectiveMode.rawValue,
      fallback: requestedMode != effectiveMode,
      viewWidth: dimension(viewWidth), viewHeight: dimension(viewHeight),
      hostWidth: dimension(hostWidth), hostHeight: dimension(hostHeight),
      hostingMounted: hostingMounted, hostingInWindow: hostingInWindow,
      nativeSwitchRequired: nativeSwitchRequired, fullAccess: fullAccess,
      appGroupAvailable: AppGroup.containerURL != nil,
      hostHint: safeHostHint(hostBundleHint),
      firstLoadForBuild: firstLoadForBuild, inputModeProbe: inputModeProbe,
      processMemory: processMemory,
      renderProbe: renderProbe
    )
    if event.needsImmediateWrite {
      queue.sync { append(entry) }
    } else {
      queue.async { append(entry) }
    }
    #endif
  }

  private static func dimension(_ value: CGFloat) -> Int {
    guard value.isFinite else { return -1 }
    return max(-1, min(4_096, Int(value.rounded())))
  }

  private static func safeHostHint(_ raw: String?) -> String {
    guard let raw, !raw.isEmpty else { return "unknown" }
    return raw.lowercased().contains("whatsapp") ? "whatsapp-last-known" : "other-last-known"
  }

  private static func append(_ entry: Entry) {
    guard let url = fileURL, var data = try? JSONEncoder().encode(entry) else { return }
    data.append(10)
    let existed = FileManager.default.fileExists(atPath: url.path)
    let fd = url.path.withCString { open($0, O_RDWR | O_CREAT | O_APPEND, mode_t(0o600)) }
    guard fd >= 0 else { return }
    defer { _ = close(fd) }
    guard flock(fd, LOCK_EX) == 0 else { return }
    defer { _ = flock(fd, LOCK_UN) }
    let size = lseek(fd, 0, SEEK_END)
    guard data.count <= Int(maxBytes), size >= 0 else { return }
    if size + off_t(data.count) > maxBytes {
      guard ftruncate(fd, 0) == 0 else { return }
    }
    data.withUnsafeBytes { raw in
      guard let start = raw.baseAddress else { return }
      var written = 0
      while written < raw.count {
        let count = write(fd, start.advanced(by: written), raw.count - written)
        guard count > 0 else { break }
        written += count
      }
    }
    #if os(iOS)
    if !existed {
      try? FileManager.default.setAttributes(
        [.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication],
        ofItemAtPath: url.path
      )
    }
    #endif
  }

  private static func readLog() -> Data {
    guard let url = fileURL else { return Data() }
    let fd = url.path.withCString { open($0, O_RDONLY) }
    guard fd >= 0 else { return Data() }
    defer { _ = close(fd) }
    guard flock(fd, LOCK_SH) == 0 else { return Data() }
    defer { _ = flock(fd, LOCK_UN) }
    return (try? Data(contentsOf: url)) ?? Data()
  }

  private static func entries() -> [[String: Any]] {
    let data = queue.sync { readLog() }
    return data.split(separator: 10).compactMap { bytes in
      guard let object = try? JSONSerialization.jsonObject(with: Data(bytes)) else { return nil }
      return object as? [String: Any]
    }
  }

  static var eventCount: Int { entries().count }

  private static func renderReview(for events: [[String: Any]]) -> [String: Any] {
    let checkpoints = events.filter { $0["renderProbe"] is [String: Any] }
    let suspicious = checkpoints.filter { ($0["event"] as? String) == Event.renderSuspicious.rawValue }
    return [
      "checkpointCount": checkpoints.count,
      "suspiciousCount": suspicious.count,
      "recentCheckpoints": Array(checkpoints.suffix(6)),
      "interpretation": "Structural checks only: a mounted or hittable view does not prove pixels were drawn."
    ]
  }

  /// A separate export summary for keyboard field clears and lifecycle changes.
  /// Clearing the input may follow Send; it does not prove Send was pressed.
  private static func postSubmitReview(for events: [[String: Any]]) -> [String: Any] {
    let names: Set<String> = [
      Event.hostTextCleared.rawValue, Event.documentChanged.rawValue,
      Event.willAppear.rawValue, Event.didAppear.rawValue,
      Event.willDisappear.rawValue, Event.didDisappear.rawValue,
      Event.renderCheckpoint.rawValue, Event.renderSuspicious.rawValue,
      Event.renderRefreshRequested.rawValue
    ]
    let recent: [[String: Any]] = events.compactMap { item in
      guard let event = item["event"] as? String, names.contains(event) else { return nil }
      return [
        "timestampMs": item["timestampMs"] ?? 0,
        "session": item["session"] ?? "",
        "event": event,
        "viewHeight": item["viewHeight"] ?? 0,
        "hostHeight": item["hostHeight"] ?? 0,
        "hostingInWindow": item["hostingInWindow"] ?? false,
        "hostHint": item["hostHint"] ?? "unknown",
        "renderCheckpoint": (item["renderProbe"] as? [String: Any])?["checkpoint"] ?? ""
      ]
    }
    // Export-only correlation: iOS may dispose of a keyboard extension
    // without calling didDisappear, which is not evidence of a crash.
    var beganDisappearing = Set<String>()
    var completedDisappearing = Set<String>()
    for item in events {
      guard let session = item["session"] as? String,
            let event = item["event"] as? String else { continue }
      if event == Event.willDisappear.rawValue { beganDisappearing.insert(session) }
      if event == Event.didDisappear.rawValue { completedDisappearing.insert(session) }
    }
    let missingCompletion = beganDisappearing.subtracting(completedDisappearing)
    return [
      "fieldClearCount": events.filter { ($0["event"] as? String) == Event.hostTextCleared.rawValue }.count,
      "sessionsWithUnmatchedWillDisappear": missingCompletion.count,
      "recentUnmatchedSessions": Array(missingCompletion.sorted().prefix(8)),
      "recentTransitions": Array(recent.suffix(80)),
      "interpretation": "Unmatched disappear callbacks can be normal iOS extension disposal. Correlate timestamps with user-observed blank keyboards."
    ]
  }

  /// Memory is sampled on lifecycle transitions and an infrequent timer.
  /// A new process after an unfinished session may be a normal iOS switch;
  /// only a system JetsamEvent or crash report can confirm termination cause.
  private static func memoryReview(for events: [[String: Any]]) -> [String: Any] {
    var samples = [[String: Any]]()
    var processOrder = [String]()
    var lastEventByProcess = [String: [String: Any]]()
    var lastMemoryByProcess = [String: [String: Any]]()
    var peaks = [String: Int]()

    for event in events {
      let process = event["processLaunchID"] as? String ?? "legacy"
      if !processOrder.contains(process) { processOrder.append(process) }
      lastEventByProcess[process] = event
      guard let memory = event["processMemory"] as? [String: Any] else { continue }
      let footprint = memory["footprintMiB"] as? Int
      if let footprint { peaks[process] = max(peaks[process] ?? 0, footprint) }
      let sample: [String: Any] = [
        "processLaunchID": process,
        "session": event["session"] ?? "",
        "event": event["event"] ?? "",
        "timestampMs": event["timestampMs"] ?? 0,
        "footprintMiB": memory["footprintMiB"] ?? NSNull(),
        "residentMiB": memory["residentMiB"] ?? NSNull(),
        "availableMiB": memory["availableMiB"] ?? NSNull(),
        "estimatedBudgetMiB": memory["estimatedBudgetMiB"] ?? NSNull()
      ]
      samples.append(sample)
      lastMemoryByProcess[process] = sample
    }
    let summaries: [[String: Any]] = processOrder.suffix(12).map { process in
      let lastEvent = lastEventByProcess[process] ?? [:]
      return [
        "processLaunchID": process,
        "lastEvent": lastEvent["event"] ?? "unknown",
        "lastEventMs": lastEvent["timestampMs"] ?? 0,
        "lastMemory": lastMemoryByProcess[process] ?? [:],
        "observedPeakFootprintMiB": peaks[process].map { $0 as Any } ?? NSNull()
      ]
    }
    let available = samples.compactMap { $0["availableMiB"] as? Int }
    let footprints = samples.compactMap { $0["footprintMiB"] as? Int }
    return [
      "sampleCount": samples.count,
      "processLaunchCount": processOrder.filter { $0 != "legacy" }.count,
      "memoryWarningCount": events.filter {
        ($0["event"] as? String) == Event.memoryWarning.rawValue
      }.count,
      "peakFootprintMiB": footprints.max().map { $0 as Any } ?? NSNull(),
      "minimumHeadroomMiB": available.min().map { $0 as Any } ?? NSNull(),
      "recentSamples": Array(samples.suffix(36)),
      "recentProcessLaunches": summaries,
      "interpretation": "Headroom is advisory. New process launches or missing dismissal callbacks do not prove OOM; check device JetsamEvent or crash logs."
    ]
  }

  /// Correlate transient UIKit document-ID gaps with extension lifecycle.
  /// Never export the document identifier or any host text.
  private static func documentIdentityReview(for events: [[String: Any]]) -> [String: Any] {
    let transitionEvents = Set([
      Event.documentIdentifierUnavailable.rawValue,
      Event.documentIdentifierRecovered.rawValue
    ])
    let transitions: [[String: Any]] = events.compactMap { entry in
      guard let event = entry["event"] as? String,
            transitionEvents.contains(event) else { return nil }
      return [
        "timestampMs": entry["timestampMs"] ?? 0,
        "session": entry["session"] ?? "",
        "processLaunchID": entry["processLaunchID"] ?? "",
        "event": event
      ]
    }
    return [
      "unavailableCount": transitions.filter {
        ($0["event"] as? String) == Event.documentIdentifierUnavailable.rawValue
      }.count,
      "recoveredCount": transitions.filter {
        ($0["event"] as? String) == Event.documentIdentifierRecovered.rawValue
      }.count,
      "recentTransitions": Array(transitions.suffix(24)),
      "interpretation": "A missing ID does not establish a host-field change. A crash report is required to confirm termination."
    ]
  }

  private static func inputModeReview(for events: [[String: Any]]) -> [String: Any] {
    let checkpoints = events.filter { $0["inputModeProbe"] is [String: Any] }
    let startup = events.last { ($0["event"] as? String) == Event.loadViewStarting.rawValue }
    let unavailable = checkpoints.filter {
      ($0["inputModeProbe"] as? [String: Any])?["documentModePresent"] as? Bool == false
    }
    let recent = checkpoints.suffix(12).map { event in
      [
        "timestampMs": event["timestampMs"] ?? 0,
        "session": event["session"] ?? "",
        "event": event["event"] ?? "",
        "inputModeProbe": event["inputModeProbe"] ?? [:],
      ] as [String: Any]
    }
    return [
      "latestStartupFirstLoadForBuild": startup?["firstLoadForBuild"] ?? NSNull(),
      "checkpointCount": checkpoints.count,
      "documentModeUnavailableCount": unavailable.count,
      "recentCheckpoints": recent,
      "interpretation": "The document mode language can be absent or stale. The extension primary language is its own declaration; available languages are installed modes, not the selected keyboard. No callbacks can be guaranteed while iOS runs another keyboard."
    ]
  }

  static func exportJSON() -> String {
    let events = entries()
    let document: [String: Any] = [
      "schemaVersion": 5,
      "exportedAtMs": Int64(Date().timeIntervalSince1970 * 1_000),
      "appBuild": Bundle.main.infoDictionary?["AltboardBuildSHA"] as? String ?? "unknown",
      "keyboardBuild": AppGroup.sharedDefaults?.string(forKey: "canto.keyboardBuildSHA") ?? "unknown",
      "captureScope": "keyboard extension only; cannot inspect another active keyboard",
      "captureEnabled": captureEnabled,
      "captureStatus": captureEnabled ? "opt-in development tracing" : "disabled for recovery; retained events may be from older builds",
      "privacy": "No keystrokes, host text, touch positions, audio or transcripts",
      "events": events,
      "renderReview": renderReview(for: events),
      "inputModeReview": inputModeReview(for: events),
      "postSubmitReview": postSubmitReview(for: events),
      "documentIdentityReview": documentIdentityReview(for: events),
      "memoryReview": memoryReview(for: events),
      "evidenceReview": KeyboardDiagnosticReview.summarize(events),
      "exportDeviceOSVersion": ProcessInfo.processInfo.operatingSystemVersionString,
    ]
    guard let data = try? JSONSerialization.data(withJSONObject: document, options: [.prettyPrinted, .sortedKeys])
    else { return "{\"schemaVersion\":1,\"events\":[]}" }
    return String(decoding: data, as: UTF8.self)
  }

  static func exportFileURL() -> URL? {
    let url = FileManager.default.temporaryDirectory
      .appendingPathComponent("Altboard-Keyboard-Trace-\(Int(Date().timeIntervalSince1970)).json")
    guard let data = exportJSON().data(using: .utf8) else { return nil }
    do { try data.write(to: url, options: .atomic); return url }
    catch { return nil }
  }

  static func clear() {
    queue.sync {
      guard let url = fileURL else { return }
      let fd = url.path.withCString { open($0, O_RDWR) }
      guard fd >= 0 else { return }
      defer { _ = close(fd) }
      guard flock(fd, LOCK_EX) == 0 else { return }
      defer { _ = flock(fd, LOCK_UN) }
      _ = ftruncate(fd, 0)
    }
  }
}
