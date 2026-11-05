import Foundation

enum LLMDevicePolicy {
  enum Tier: Int, CaseIterable { case compact, balanced, large }

  static func usesChinese(_ languages: [String]) -> Bool {
    languages.contains {
      let code = $0.lowercased().replacingOccurrences(of: "_", with: "-")
        .split(separator: "-").first.map(String.init) ?? ""
      return code == "yue" || code == "zh" || code == "cmn"
    }
  }

  static func requiredMemoryBytes(for tier: Tier) -> UInt64 {
    let workingMB: UInt64
    switch tier {
    case .compact: workingMB = 850
    case .balanced: workingMB = 1_900
    case .large: workingMB = 7_000
    }
    return workingMB * 1_000_000 * 12 / 10
  }

  static func supports(_ tier: Tier, physicalBytes: UInt64, availableBytes: UInt64) -> Bool {
    let minimumPhysical: UInt64
    switch tier {
    case .compact: minimumPhysical = 3_000_000_000
    case .balanced: minimumPhysical = 6_000_000_000
    case .large: minimumPhysical = 12_000_000_000
    }
    return physicalBytes >= minimumPhysical && availableBytes >= self.requiredMemoryBytes(for: tier)
  }

  static func recommendedTier(physicalBytes: UInt64, availableBytes: UInt64) -> Tier {
    for tier in [Tier.large, .balanced] {
      if self.supports(tier, physicalBytes: physicalBytes, availableBytes: availableBytes) { return tier }
    }
    return .compact
  }
}
