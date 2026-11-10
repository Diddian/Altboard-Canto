import Foundation

/// Pinned INT8 Cantonese-finetuned SenseVoice bundle. Never inspect or run an
/// unverified ONNX file from a partial or cancelled download.
enum SenseVoiceModelBundle {
  static let modelSHA256 =
    "12ca1a2ae7ecf3e0019ef2822307ee0b5cadc9196569e379b4c4026f8205276d"
  static let repository =
    "csukuangfj/sherpa-onnx-sense-voice-zh-en-ja-ko-yue-int8-2025-09-09"
  static let markerName = ".sensevoice-sha256"

  static func locate(in directory: URL) -> URL? {
    let fm = FileManager.default
    let model = directory.appendingPathComponent("model.int8.onnx")
    let tokens = directory.appendingPathComponent("tokens.txt")
    let marker = directory.appendingPathComponent(markerName)
    guard (try? String(contentsOf: marker, encoding: .utf8))?
          .trimmingCharacters(in: .whitespacesAndNewlines) == modelSHA256,
          let modelSize = (try? fm.attributesOfItem(atPath: model.path))?[.size] as? NSNumber,
          modelSize.int64Value > 200_000_000,
          let tokenSize = (try? fm.attributesOfItem(atPath: tokens.path))?[.size] as? NSNumber,
          tokenSize.int64Value > 100_000, tokenSize.int64Value < 1_000_000
    else { return nil }
    return directory
  }

  static func isValid(directory: URL) -> Bool { locate(in: directory) != nil }
}
