import Foundation

enum Qwen3ModelBundle {
  static let required = [
    "conv_frontend.onnx",
    "tokenizer/vocab.json",
    "tokenizer/merges.txt",
    "tokenizer/tokenizer_config.json",
  ]

  static func locate(in root: URL) -> URL? {
    let fm = FileManager.default
    guard fm.fileExists(atPath: root.path) else { return nil }
    let candidates = [root] + ((try? fm.contentsOfDirectory(at: root, includingPropertiesForKeys: nil)) ?? [])
    return candidates.first { directory in
      required.allSatisfy { fm.fileExists(atPath: directory.appendingPathComponent($0).path) }
        && file(prefix: "encoder", in: directory) != nil
        && file(prefix: "decoder", in: directory) != nil
    }
  }

  static func isValid(directory: URL) -> Bool { locate(in: directory) != nil }

  static func file(prefix: String, in directory: URL) -> String? {
    let candidates = (try? FileManager.default.contentsOfDirectory(
      at: directory, includingPropertiesForKeys: nil
    )) ?? []
    return candidates.first {
      $0.lastPathComponent.hasPrefix(prefix) && $0.pathExtension == "onnx"
    }?.path
  }
}
