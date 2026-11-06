import Foundation

// Test-only stand-in for the signed iOS App Group resolver.
enum AppGroup {
  static let containerURL: URL? = FileManager.default.temporaryDirectory
    .appendingPathComponent(UUID().uuidString)
  static var sharedDefaults: UserDefaults? { nil }
}

@main
private enum RecoverySmoke {
  static func main() throws {
    let directory = AppGroup.containerURL!
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    let file = directory.appendingPathComponent("keyboard-lifecycle-v1.jsonl")
    precondition(!KeyboardLifecycleTrace.captureEnabled)
    KeyboardLifecycleTrace.record(
      .memoryWarning, session: "test", requestedMode: .alphabetic, effectiveMode: .alphabetic,
      viewWidth: 440, viewHeight: 277, hostWidth: 440, hostHeight: 277,
      hostingMounted: true, hostingInWindow: true, nativeSwitchRequired: false,
      fullAccess: true, hostBundleHint: nil
    )
    // eventCount drains the serial queue, so this catches async writes too.
    precondition(KeyboardLifecycleTrace.eventCount == 0)
    precondition(!FileManager.default.fileExists(atPath: file.path))
    let legacy = "{\"timestampMs\":1,\"processLaunchID\":\"old\",\"event\":\"memoryWarning\"}\n"
    try Data(legacy.utf8).write(to: file)
    let json = Data(KeyboardLifecycleTrace.exportJSON().utf8)
    let report = try JSONSerialization.jsonObject(with: json) as! [String: Any]
    precondition(report["captureEnabled"] as? Bool == false)
    precondition((report["events"] as! [[String: Any]]).count == 1)
    let retained = try Data(contentsOf: file)
    precondition(retained == Data(legacy.utf8))
    print("Recovery: default tracing disabled, no file writes, legacy export retained PASS")
  }
}
