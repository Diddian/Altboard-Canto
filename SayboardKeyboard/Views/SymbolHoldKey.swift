import SwiftUI

/// Immediate UIKit touch ownership and native-like horizontal hold selection.
/// Shared by Cantonese, English, German, numbers and symbol pages.
struct SymbolHoldKey: View {
  let symbol: String
  var face: String? = nil
  var fixedWidth: CGFloat? = nil
  var column = 0
  var columnCount = 10
  let onInsert: (String) -> Void

  @State private var pressed = false
  @State private var recentlyPressed = false
  @State private var showingOptions = false
  @State private var selectedIndex = 0
  @State private var beganAt: CGFloat = 0
  @State private var holdTask: Task<Void, Never>?
  @State private var highlightTask: Task<Void, Never>?

  private var options: [String] {
    SymbolKeyAlternates.choices(for: self.symbol)
  }

  private var expandsLeft: Bool {
    self.column >= self.columnCount / 2
  }

  var body: some View {
    Text(verbatim: self.face ?? self.symbol)
      .font(.system(size: 18.kbScaled))
      .foregroundStyle(.primary)
      .frame(maxWidth: .infinity)
      .frame(width: self.fixedWidth, height: KeyboardChromeMetrics.keyHeight)
      .background(
        Color(uiColor: self.pressed || self.recentlyPressed
          ? KeyboardPalette.pressedFill : KeyboardPalette.keyFill),
        in: RoundedRectangle(cornerRadius: 8.5.kbScaled)
      )
      .contentShape(Rectangle())
      .overlay {
        ImmediateKeyTouchSurface(
          onBegan: { point in self.begin(at: point) },
          onMoved: { point, _ in self.move(to: point) },
          onEnded: { point in self.end(at: point) },
          onCancelled: { self.reset() }
        )
        .accessibilityHidden(true)
      }
      .overlay(alignment: .topLeading) {
        if self.showingOptions && self.options.count > 1 {
          self.alternatesPopup
            .offset(x: self.popupOffset, y: -51.kbScaled)
            .allowsHitTesting(false)
            .accessibilityHidden(true)
        }
      }
      .zIndex(self.showingOptions ? 100 : 0)
      .accessibilityElement()
      .accessibilityAddTraits(.isButton)
      .accessibilityLabel(self.symbol)
      .accessibilityHint(self.options.count > 1 ? "Touch and hold for related symbols" : "")
      .accessibilityAction { self.onInsert(self.symbol) }
      .onDisappear {
        self.holdTask?.cancel()
        self.highlightTask?.cancel()
      }
  }

  private var popupWidth: CGFloat {
    CGFloat(self.options.count) * 36.kbScaled + 12.kbScaled
  }

  private var popupOffset: CGFloat {
    let width = self.fixedWidth ?? 35.kbScaled
    if self.column <= 1 { return 0 }
    if self.column >= self.columnCount - 2 { return width - self.popupWidth }
    return (width - self.popupWidth) / 2
  }

  private var alternatesPopup: some View {
    HStack(spacing: 0) {
      ForEach(Array(self.options.enumerated()), id: \.offset) { index, symbol in
        Text(verbatim: symbol)
          .font(.system(size: 21.kbScaled))
          .fontWidth(.condensed)
          .foregroundStyle(.primary)
          .frame(width: 36.kbScaled, height: 43.kbScaled)
          .background {
            if index == self.selectedIndex {
              RoundedRectangle(cornerRadius: 7.kbScaled)
                .fill(Color(uiColor: KeyboardPalette.pressedFill))
            }
          }
      }
    }
    .padding(6.kbScaled)
    .background(
      Color(uiColor: KeyboardPalette.keyFill),
      in: RoundedRectangle(cornerRadius: 18.kbScaled, style: .continuous)
    )
    .shadow(color: .black.opacity(0.26), radius: 4.kbScaled, y: 2.kbScaled)
  }

  private func begin(at point: CGPoint) {
    self.reset()
    self.highlightTask?.cancel()
    self.recentlyPressed = false
    self.pressed = true
    self.beganAt = point.x
    KeyboardHaptics.key()
    guard self.options.count > 1 else { return }
    self.holdTask = Task { @MainActor in
      do { try await Task.sleep(for: .milliseconds(310)) } catch { return }
      guard !Task.isCancelled, self.pressed else { return }
      self.showingOptions = true
      self.selectedIndex = 0
      KeyboardHaptics.key()
    }
  }

  private func move(to point: CGPoint) {
    guard self.pressed && self.showingOptions else { return }
    let delta = self.expandsLeft ? self.beganAt - point.x : point.x - self.beganAt
    self.selectedIndex = min(self.options.count - 1,
      max(0, Int(max(0, delta) / 36.kbScaled)))
  }

  private func end(at point: CGPoint) {
    guard self.pressed else { return }
    self.move(to: point)
    let selected = self.showingOptions
      ? self.options[self.selectedIndex] : self.symbol
    self.reset()
    self.recentlyPressed = true
    self.highlightTask = Task { @MainActor in
      do { try await Task.sleep(for: .milliseconds(80)) } catch { return }
      guard !Task.isCancelled else { return }
      self.recentlyPressed = false
    }
    self.onInsert(selected)
  }

  private func reset() {
    self.holdTask?.cancel()
    self.holdTask = nil
    self.showingOptions = false
    self.pressed = false
  }
}
