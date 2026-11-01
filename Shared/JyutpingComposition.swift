import Foundation

/// Pre-edit buffer; input is never sent to the host until commit.
struct JyutpingComposition: Equatable {
  private(set) var buffer = ""

  var isEmpty: Bool { buffer.isEmpty }

  @discardableResult
  mutating func append(_ key: String) -> Bool {
    let value = key.lowercased()
    guard value.count == 1, buffer.count < 48,
          value.allSatisfy({ $0.isASCII && ($0.isLetter || "123456".contains($0)) })
    else { return false }
    buffer.append(value)
    return true
  }

  @discardableResult
  mutating func backspace() -> Bool {
    guard !buffer.isEmpty else { return false }
    buffer.removeLast()
    return true
  }

  mutating func clear() { buffer = "" }
}
