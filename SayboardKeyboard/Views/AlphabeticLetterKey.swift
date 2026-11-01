import SwiftUI

/// A regular-weight iOS-size letter key. Hold for accented alternatives,
/// slide across the popup, and release to insert the selected character.
struct AlphabeticLetterKey: View {
  let letter: String
  let uppercase: Bool
  let column: Int
  let rowCount: Int
  let onInsert: (String) -> Void

  @State private var pressed = false
  @State private var choosing = false
  @State private var selected = 0
  @State private var holdTask: Task<Void, Never>?

  private var options: [String] {
    LetterKeyAlternates.choices(for: self.letter, uppercase: self.uppercase)
  }

  private var popupAlignment: Alignment {
    if self.column <= 2 { return .topLeading }
    if self.column >= self.rowCount - 3 { return .topTrailing }
    return .top
  }

  var body: some View {
    Text(verbatim: self.uppercase ? self.letter.uppercased() : self.letter.lowercased())
      .font(.system(size: 23.kbScaled, weight: .regular, design: .default))
      .foregroundStyle(.primary)
      .frame(maxWidth: .infinity)
      .frame(height: KeyboardChromeMetrics.keyHeight)
      .background {
        RoundedRectangle(cornerRadius: 5.5.kbScaled, style: .continuous)
          .fill(Color(self.pressed ? .keyPressedBackground : .keyBackground))
          .shadow(color: .black.opacity(0.13), radius: 0.5, y: 0.5)
      }
      .contentShape(Rectangle())
      .overlay(alignment: self.popupAlignment) {
        if self.choosing {
          self.alternatePopup
            .fixedSize(horizontal: true, vertical: true)
            .offset(y: -49.kbScaled)
            .allowsHitTesting(false)
            .transition(.identity)
        }
      }
      .zIndex(self.choosing ? 100 : 0)
      .gesture(
        DragGesture(minimumDistance: 0)
          .onChanged { value in
            if !self.pressed { self.beginPress() }
            if self.choosing {
              let index = Int(abs(value.translation.width) / 32.kbScaled)
              self.selected = min(max(index, 0), self.options.count - 1)
            }
          }
          .onEnded { _ in self.endPress() }
      )
      .onDisappear {
        self.holdTask?.cancel()
        self.pressed = false
        self.choosing = false
      }
      .accessibilityLabel(self.options.first ?? self.letter)
      .accessibilityHint(self.options.count > 1 ? "Hold for accented letters" : "")
  }

  private var alternatePopup: some View {
    HStack(spacing: 0) {
      ForEach(Array(self.options.enumerated()), id: \.offset) { index, option in
        Text(verbatim: option)
          .font(.system(size: 22.kbScaled))
          .foregroundStyle(index == self.selected ? Color.white : Color.primary)
          .frame(width: 33.kbScaled, height: 43.kbScaled)
          .background {
            if index == self.selected {
              RoundedRectangle(cornerRadius: 5.kbScaled)
                .fill(Color.accentColor)
            }
          }
      }
    }
    .padding(3.kbScaled)
    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 9.kbScaled))
    .shadow(color: .black.opacity(0.23), radius: 3, y: 2)
  }

  private func beginPress() {
    self.pressed = true
    KeyboardHaptics.key()
    guard self.options.count > 1 else { return }
    self.holdTask?.cancel()
    self.holdTask = Task { @MainActor in
      do { try await Task.sleep(for: .milliseconds(380)) } catch { return }
      guard !Task.isCancelled, self.pressed else { return }
      self.choosing = true
      self.selected = 0
      KeyboardHaptics.key(strength: 0.35)
    }
  }

  private func endPress() {
    self.holdTask?.cancel()
    self.holdTask = nil
    guard self.pressed else { return }
    let index = self.choosing ? self.selected : 0
    self.onInsert(self.options[index])
    self.pressed = false
    self.choosing = false
    self.selected = 0
  }
}
