import Testing

@Suite("Basic typing without keyboard permissions")
struct BasicKeyboardFallbackTests {
  @Test @MainActor
  func noFullAccessStillProvidesAlphabeticTyping() {
    let state = KeyboardState()
    state.keyboardKind = .standard
    state.hasFullAccess = false
    #expect(state.requiresBasicTypingFallback)
    #expect(state.effectiveTypingKind == .alphabetic)
    state.keyboardKind = .extended
    #expect(state.effectiveTypingKind == .alphabetic)
    state.keyboardKind = .alphabetic
    #expect(!state.requiresBasicTypingFallback)
    #expect(state.effectiveTypingKind == .alphabetic)
  }
}
