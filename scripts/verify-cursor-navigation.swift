import Foundation

@main
struct CursorLineNavigationSmoke {
  static func main() {
    let up = CursorLineNavigation.move(
      direction: -1, before: "hello world\nabc", after: "\nlast")
    precondition(up?.characterOffset == -12, "up should preserve column")
    precondition(up?.preferredColumn == 3)
    let down = CursorLineNavigation.move(
      direction: 1, before: "hello\nabc", after: "def\nxx\nend")
    precondition(down?.characterOffset == 6, "down should clamp next line")
    precondition(down?.preferredColumn == 3)
    let again = CursorLineNavigation.move(
      direction: 1, before: "hello\nabcdef\nxx", after: "\nlonger",
      preferredColumn: down?.preferredColumn)
    precondition(again?.characterOffset == 4, "column preference survives short lines")
    precondition(CursorLineNavigation.move(
      direction: -1, before: "single line", after: nil) == nil)
    precondition(CursorLineNavigation.move(
      direction: 1, before: "short", after: "no newline") == nil)
    precondition(CursorLineNavigation.move(
      direction: 1, before: nil, after: "\nnext") == nil)
    print("Explicit-line 2D caret navigation: PASS")
  }
}
