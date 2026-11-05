import Foundation
#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#endif

/// Milestone-only diagnostics shared by the app and keyboard extension.
/// Do not accept text, paths, host identifiers, prompts or typed characters.
enum FeatureDiagnostics {
  enum Area: String, Sendable {
    case speech, liveDictation, voiceOutput, aiActions, speechModel, textModel
    case meeting, data, language, swipe, chineseInput
  }

  enum Event: String, Sendable {
    case started, completed, stopped, cancelled, failed, blocked, fallback
    case selected, queued, downloaded, deleted, slow, noSpeech, rejected
    case unavailable, interrupted, firstUpdate
  }

  private struct Entry: Codable, Sendable {
    let timestampMs: Int64
    let process: String
    let area: String
    let event: String
    let durationMs: Int?
  }

  private static let filename = "feature-diagnostics-v1.jsonl"
  private static let maxBytes: off_t = 1_048_576
  private static let queue = DispatchQueue(label: "app.sayboard.featureDiagnostics", qos: .utility)
  private static var fileURL: URL? { AppGroup.containerURL?.appendingPathComponent(filename) }

  static func record(_ area: Area, _ event: Event, durationMs: Int? = nil) {
    #if !APPSTORE
    let entry = Entry(
      timestampMs: Int64(Date().timeIntervalSince1970 * 1_000),
      process: Bundle.main.bundleURL.pathExtension == "appex" ? "keyboard" : "app",
      area: area.rawValue, event: event.rawValue,
      durationMs: durationMs.map { max(0, min(600_000, $0)) }
    )
    if event == .failed || event == .interrupted {
      queue.sync { append(entry) }
    } else {
      queue.async { append(entry) }
    }
    #endif
  }

  private static func append(_ entry: Entry) {
    guard let url = fileURL, var bytes = try? JSONEncoder().encode(entry) else { return }
    bytes.append(10)
    let isNew = !FileManager.default.fileExists(atPath: url.path)
    let fd = url.path.withCString { open($0, O_RDWR | O_CREAT | O_APPEND, mode_t(0o600)) }
    guard fd >= 0 else { return }
    defer { _ = close(fd) }
    guard flock(fd, LOCK_EX) == 0 else { return }
    defer { _ = flock(fd, LOCK_UN) }
    let currentSize = lseek(fd, 0, SEEK_END)
    if currentSize >= 0 && currentSize + off_t(bytes.count) > maxBytes {
      _ = ftruncate(fd, 0)
    }
    bytes.withUnsafeBytes { raw in
      guard let start = raw.baseAddress else { return }
      var offset = 0
      while offset < raw.count {
        let count = write(fd, start.advanced(by: offset), raw.count - offset)
        guard count > 0 else { break }
        offset += count
      }
    }
    #if os(iOS)
    if isNew {
      try? FileManager.default.setAttributes(
        [.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication],
        ofItemAtPath: url.path
      )
    }
    #endif
  }

  private static func entries() -> [[String: Any]] {
    let contents: Data = queue.sync {
      guard let url = fileURL else { return Data() }
      let fd = url.path.withCString { open($0, O_RDONLY) }
      guard fd >= 0 else { return Data() }
      defer { _ = close(fd) }
      guard flock(fd, LOCK_SH) == 0 else { return Data() }
      defer { _ = flock(fd, LOCK_UN) }
      return (try? Data(contentsOf: url)) ?? Data()
    }
    return contents.split(separator: 10).compactMap { line in
      (try? JSONSerialization.jsonObject(with: Data(line))) as? [String: Any]
    }
  }

  static var eventCount: Int { entries().count }

  static func exportJSON() -> String {
    let keyboardJSON = Data(KeyboardLifecycleTrace.exportJSON().utf8)
    let keyboard = (try? JSONSerialization.jsonObject(with: keyboardJSON))
      ?? ["events": []]
    let swipeCountersData = try? JSONEncoder().encode(KeyboardExperimentMetrics.read())
    let swipeCounters = swipeCountersData.flatMap {
      try? JSONSerialization.jsonObject(with: $0)
    } ?? [:]
    let payload: [String: Any] = [
      "schemaVersion": 1,
      "exportedAtMs": Int64(Date().timeIntervalSince1970 * 1_000),
      "build": Bundle.main.infoDictionary?["AltboardBuildSHA"] as? String ?? "unknown",
      "privacy": "No typed text, host content, touch paths, audio, transcripts or credentials",
      "features": entries(),
      "keyboardLifecycle": keyboard,
      "existingAggregates": [
        "hapticRequestCount": KeyboardHapticTrace.total,
        "hapticRequestSamples": KeyboardHapticTrace.events,
        "swipeTouchCounters": swipeCounters,
      ] as [String: Any],
    ]
    guard let data = try? JSONSerialization.data(
      withJSONObject: payload, options: [.prettyPrinted, .sortedKeys]
    ) else { return "{}" }
    return String(decoding: data, as: UTF8.self)
  }

  static func exportFileURL() -> URL? {
    let path = FileManager.default.temporaryDirectory
      .appendingPathComponent("Altboard-Development-Diagnostics-\(Int(Date().timeIntervalSince1970)).json")
    guard let data = exportJSON().data(using: .utf8) else { return nil }
    do { try data.write(to: path, options: .atomic); return path }
    catch { return nil }
  }

  static func clearAll() {
    queue.sync {
      guard let url = fileURL else { return }
      let fd = url.path.withCString { open($0, O_RDWR) }
      guard fd >= 0 else { return }
      defer { _ = close(fd) }
      guard flock(fd, LOCK_EX) == 0 else { return }
      defer { _ = flock(fd, LOCK_UN) }
      _ = ftruncate(fd, 0)
    }
    KeyboardLifecycleTrace.clear()
  }
}
