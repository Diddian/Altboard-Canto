import Testing

@Suite("Safe vertical keyboard caret motion")
struct CursorLineNavigationTests {
  @Test func explicitNewlines() {
    let up = CursorLineNavigation.move(
      direction: -1, before: "hello world\nabc", after: "def\nnext")
    #expect(up?.characterOffset == -12)
    #expect(up?.preferredColumn == 3)
    let down = CursorLineNavigation.move(
      direction: 1, before: "first\nabc", after: "def\nxx\nlast")
    #expect(down?.characterOffset == 6)
    #expect(down?.preferredColumn == 3)
  }

  @Test func noUnverifiedSoftWrap() {
    #expect(CursorLineNavigation.move(direction: -1,
      before: "visually wrapped text without hard newline", after: "") == nil)
    #expect(CursorLineNavigation.move(direction: 1,
      before: "abc", after: "def") == nil)
  }
}
