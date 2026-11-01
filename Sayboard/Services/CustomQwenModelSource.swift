import Foundation

enum CustomQwenModelSource {
  private static let urlKey = "canto.qwen3.modelURL"
  private static let shaKey = "canto.qwen3.sha256"
  static var url: String {
    get { UserDefaults.standard.string(forKey: urlKey) ?? "" }
    set { UserDefaults.standard.set(newValue, forKey: urlKey) }
  }
  static var sha256: String {
    get { UserDefaults.standard.string(forKey: shaKey) ?? "" }
    set { UserDefaults.standard.set(newValue.lowercased(), forKey: shaKey) }
  }
  static func entry() -> ModelEntry? {
    guard let address = URL(string: url), address.scheme == "https",
      let host = address.host, !host.isEmpty, address.user == nil, address.password == nil,
      sha256.range(of: "^[a-f0-9]{64}$", options: .regularExpression) != nil
    else { return nil }
    return ModelEntry(url: address, sha256: sha256, sizeBytes: 4_000_000_000,
                      expandedBytes: 6_000_000_000, engine: .qwen3)
  }
}
