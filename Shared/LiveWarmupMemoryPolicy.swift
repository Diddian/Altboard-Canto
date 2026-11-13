/// Admission control, not a guarantee against iOS memory termination.
enum LiveWarmupMemoryPolicy {
  static func requiredAvailableMB(requirementMB: Int, wantsLive: Bool) -> Int {
    let requirement = max(0, requirementMB)
    return wantsLive ? max(2_400, Int(Double(requirement) * 0.58)) : requirement + 512
  }

  static func allowsWarmup(availableMB: Int, requirementMB: Int, wantsLive: Bool) -> Bool {
    availableMB >= requiredAvailableMB(requirementMB: requirementMB, wantsLive: wantsLive)
  }
}
