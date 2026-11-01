import Foundation

enum CantoneseOutput {
  /// Preserve English and German spans. A full OpenCC s2hk dictionary will be added after model tests.
  static func normalize(_ text: String) -> String {
    guard text.unicodeScalars.contains(where: { (0x3400...0x9FFF).contains($0.value) }) else { return text }
    return text.applyingTransform(StringTransform("Hans-Hant"), reverse: false) ?? text
  }
}
