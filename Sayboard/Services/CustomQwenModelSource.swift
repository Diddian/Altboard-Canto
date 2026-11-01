import Foundation

/// A Hugging Face repository, not a standalone MLX/GGUF model or ZIP URL.
enum CustomQwenModelSource {
  static let largeDefault = "thieunv/sherpa-onnx-qwen3-asr-1.7B-int8"
  static let smallDefault = "csukuangfj2/sherpa-onnx-qwen3-asr-0.6B-int8-2026-03-25"

  static func presets(for variant: ModelVariant) -> [String] {
    switch variant {
    case .qwen3ASR17B:
      return [largeDefault, "solavr/sherpa-onnx-qwen3-asr-1.7B-int8"]
    case .qwen3ASR06B:
      return [smallDefault, "thieunv-asilla/sherpa-onnx-qwen3-asr-0.6B-int8"]
    default:
      return []
    }
  }

  static func repositoryID(for variant: ModelVariant) -> String {
    let preferred = UserDefaults.standard.string(forKey: key(for: variant)) ?? ""
    if let valid = normalizedRepositoryID(preferred) { return valid }
    return presets(for: variant).first ?? ""
  }

  static func save(_ value: String, for variant: ModelVariant) -> Bool {
    guard let normalized = normalizedRepositoryID(value) else { return false }
    UserDefaults.standard.set(normalized, forKey: key(for: variant))
    return true
  }

  static func normalizedRepositoryID(_ input: String) -> String? {
    var value = input.trimmingCharacters(in: .whitespacesAndNewlines)
    if value.hasPrefix("https://"), let url = URL(string: value) {
      guard ["huggingface.co", "hf-mirror.com"].contains(url.host ?? "") else { return nil }
      let parts = url.pathComponents.filter { $0 != "/" }
      guard parts.count >= 2 else { return nil }
      value = parts.prefix(2).joined(separator: "/")
    }
    guard value.range(
      of: "^[A-Za-z0-9][A-Za-z0-9._-]*/[A-Za-z0-9][A-Za-z0-9._-]*$",
      options: .regularExpression
    ) != nil, !value.contains("..")
    else { return nil }
    return value
  }

  private static func key(for variant: ModelVariant) -> String {
    "canto.qwen3.huggingFaceRepository.\(variant.rawValue)"
  }
}
