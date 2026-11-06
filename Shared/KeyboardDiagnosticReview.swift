import Foundation

/// Export-only correlation of retained extension observations, never a crash detector.
/// Legacy records deliberately keep unknown identity fields rather than borrowing
/// the exporting app's build or PID. No extra sampling or observers are installed.
enum KeyboardDiagnosticReview {
  static func summarize(_ events: [[String: Any]]) -> [String: Any] {
    var order = [String]()
    var groups = [String: [[String: Any]]]()
    for event in events {
      guard let process = event["processLaunchID"] as? String else { continue }
      if groups[process] == nil { order.append(process) }
      groups[process, default: []].append(event)
    }
    let processes: [[String: Any]] = order.suffix(12).map { process in
      let retained = groups[process] ?? []
      let warnings = retained.indices.filter { retained[$0]["event"] as? String == "memoryWarning" }
      let windows: [[String: Any]] = warnings.suffix(8).map { index in
        let before = retained[..<index].last { $0["processMemory"] is [String: Any] }
        let after = retained.dropFirst(index + 1).first { $0["processMemory"] is [String: Any] }
        return [
          "callback": checkpoint(retained[index]),
          "previousMemorySample": before.map(checkpoint) ?? [:],
          "nextMemorySample": after.map(checkpoint) ?? [:]
        ]
      }
      return [
        "processLaunchID": process,
        "firstRetainedCheckpoint": retained.first.map(checkpoint) ?? [:],
        "lastRetainedCheckpoint": retained.last.map(checkpoint) ?? [:],
        "memoryWarningCallbackCount": warnings.count,
        "recentWarningWindows": windows
      ]
    }
    return [
      "processes": processes,
      "systemEvidenceAutomaticallyCollected": false,
      "manualSystemEvidence": ["kbd .ips", "SayboardKeyboard .ips", "JetsamEvent .ips"],
      "manualExportLocation": "Settings > Privacy & Security > Analytics & Improvements > Analytics Data > select report > Share",
      "correlation": "For extension reports, match process name, PID, incident time and build with checkpoints. For kbd (a different process), correlate time and OS version only. PID can be reused; uptime is monotonic only within a device boot. Export time is not incident time.",
      "limits": "Retained extension observations only. Missing callbacks do not prove a crash; multiple controllers may receive the same warning. Zero warnings do not exclude jetsam. Headroom is advisory, not a fixed memory limit. No access to kbd/system logs or another keyboard; a manual system report is required to establish termination cause."
    ]
  }

  private static func checkpoint(_ event: [String: Any]) -> [String: Any] {
    var result = [String: Any]()
    for key in ["timestampMs", "systemUptimeMs", "processID", "buildSHA", "session", "event"] {
      result[key] = event[key] ?? NSNull()
    }
    if let memory = event["processMemory"] as? [String: Any] {
      var selected = [String: Any]()
      for key in ["footprintMiB", "residentMiB", "availableMiB", "estimatedBudgetMiB"] {
        selected[key] = memory[key] ?? NSNull()
      }
      result["processMemory"] = selected
    }
    return result
  }
}
