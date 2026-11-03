import Foundation

/// Moves a text caret between explicit newline-delimited lines using the
/// limited character-offset API available to third-party iOS keyboards.
/// Soft wraps are deliberately excluded: UITextDocumentProxy has no layout
/// geometry or line-fragment rects for arbitrary host text fields.
enum CursorLineNavigation {
  struct Movement: Equatable {
    let characterOffset: Int
    let preferredColumn: Int
  }

  static func move(direction: Int, before: String?, after: String?,
                   preferredColumn: Int? = nil) -> Movement? {
    guard direction == -1 || direction == 1, let before else { return nil }
    let currentColumn = before.split(separator: "\n",
                                     omittingEmptySubsequences: false).last?.count ?? 0
    let desiredColumn = preferredColumn ?? currentColumn

    if direction < 0 {
      guard let newline = before.lastIndex(of: "\n") else { return nil }
      let preceding = before[..<newline]
      let previousLength = preceding.split(separator: "\n",
                                           omittingEmptySubsequences: false).last?.count ?? 0
      let targetColumn = min(desiredColumn, previousLength)
      let distance = currentColumn + 1 + previousLength - targetColumn
      return Movement(characterOffset: -distance, preferredColumn: desiredColumn)
    }

    guard let after, let newline = after.firstIndex(of: "\n") else { return nil }
    let currentRemainder = after[..<newline].count
    let next = after[after.index(after: newline)...]
    let nextLength = next.split(separator: "\n",
                                omittingEmptySubsequences: false).first?.count ?? 0
    let targetColumn = min(desiredColumn, nextLength)
    return Movement(characterOffset: currentRemainder + 1 + targetColumn,
                    preferredColumn: desiredColumn)
  }
}
