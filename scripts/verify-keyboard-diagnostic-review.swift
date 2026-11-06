import Foundation

@main
private enum DiagnosticReviewSmoke {
  static func main() {
    func entry(_ process: String, _ time: Int, _ event: String, _ footprint: Int? = nil) -> [String: Any] {
      var result: [String: Any] = [
        "processLaunchID": process, "timestampMs": time, "event": event,
        "processID": 123, "systemUptimeMs": time + 100, "buildSHA": "build-A",
        "session": "controller-1", "hostText": "must not be copied"
      ]
      if let footprint { result["processMemory"] = ["footprintMiB": footprint] }
      return result
    }
    func processes(_ events: [[String: Any]]) -> [[String: Any]] {
      KeyboardDiagnosticReview.summarize(events)["processes"] as! [[String: Any]]
    }
    assert(processes([]).isEmpty)
    let events = [
      entry("old", 1, "memorySample", 152), entry("old", 2, "memoryWarning", 144),
      entry("new", 3, "memorySample", 19), entry("old", 4, "memoryWarning", 144),
      entry("old", 5, "didDisappear", 151), entry("new", 6, "renderCheckpoint", 42)
    ]
    let review = KeyboardDiagnosticReview.summarize(events)
    let rows = review["processes"] as! [[String: Any]]
    assert(rows.count == 2)
    assert(rows[0]["memoryWarningCallbackCount"] as? Int == 2)
    assert(rows[1]["memoryWarningCallbackCount"] as? Int == 0)
    let windows = rows[0]["recentWarningWindows"] as! [[String: Any]]
    let previous = windows[0]["previousMemorySample"] as! [String: Any]
    let next = windows[1]["nextMemorySample"] as! [String: Any]
    assert(previous["timestampMs"] as? Int == 1)
    assert(next["timestampMs"] as? Int == 5) // Never borrow the other process's sample.
    let first = rows[0]["firstRetainedCheckpoint"] as! [String: Any]
    assert(first["buildSHA"] as? String == "build-A")
    assert(first["processID"] as? Int == 123)
    assert(first["systemUptimeMs"] as? Int == 101)
    let legacy = processes([["processLaunchID": "legacy", "event": "memoryWarning"]])[0]
    let legacyFirst = legacy["firstRetainedCheckpoint"] as! [String: Any]
    assert(legacyFirst["buildSHA"] is NSNull && legacyFirst["processID"] is NSNull)
    let legacyWindow = (legacy["recentWarningWindows"] as! [[String: Any]])[0]
    assert((legacyWindow["nextMemorySample"] as! [String: Any]).isEmpty)
    assert((legacyWindow["previousMemorySample"] as! [String: Any]).isEmpty)
    let manyProcesses = (0..<20).map { entry("p\($0)", $0, "memorySample", $0) }
    assert(processes(manyProcesses).count == 12)
    assert(processes(manyProcesses)[0]["processLaunchID"] as? String == "p8")
    let manyWarnings = (0..<20).map { entry("p", $0, "memoryWarning") }
    let bounded = processes(manyWarnings)[0]
    assert(bounded["memoryWarningCallbackCount"] as? Int == 20)
    assert((bounded["recentWarningWindows"] as! [[String: Any]]).count == 8)
    assert(review["systemEvidenceAutomaticallyCollected"] as? Bool == false)
    let json = String(decoding: try! JSONSerialization.data(withJSONObject: review), as: UTF8.self)
    assert(!json.contains("must not be copied") && !json.contains("hostText"))
    assert(json.contains("Zero warnings do not exclude jetsam"))
    print("Diagnostic review: process isolation, callback counts, legacy, bounds, privacy PASS")
  }
}
