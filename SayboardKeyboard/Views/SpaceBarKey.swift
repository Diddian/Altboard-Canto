import SwiftUI

struct SpaceBarKey: View {

  let useCustomSpaceBar: Bool
  let showsAlphabetIndicator: Bool
  let onSpace: () -> Void
  let onCursorMove: (Int) -> Void
  var onVerticalCursorMove: ((Int) -> Void)? = nil
  var onTrackingBegan: (() -> Void)? = nil
  var onTrackingEnded: (() -> Void)? = nil

  var body: some View {
    ZStack(alignment: .bottomTrailing) {
      self.label
        .foregroundStyle(.primary)
        .frame(maxWidth: .infinity)
        .frame(height: 45.kbScaled)
      if self.showsAlphabetIndicator && !self.isTrackpadActive {
        Text("A")
          .font(.system(size: 10.kbScaled, weight: .medium))
          .fontWidth(.condensed)
          .foregroundStyle(.secondary)
          .padding(.trailing, 6.kbScaled)
          .padding(.bottom, 4.kbScaled)
          .allowsHitTesting(false)
      }
    }
      .frame(maxWidth: .infinity)
      .frame(height: 45.kbScaled)
      .background {
        RoundedRectangle(cornerRadius: 8.5.kbScaled, style: .continuous)
          .fill(Color(self.isPressed ? .keyPressedBackground : .keyBackground))
          .keyPressTransition(isPressed: self.isPressed)
      }
      .gesture(
        DragGesture(minimumDistance: 0)
          .onChanged { value in
            self.handleDragChanged(value)
          }
          .onEnded { _ in
            self.handleDragEnded()
          }
      )
      .onDisappear { self.finishTracking(emitSpace: false) }
      .accessibilityHint("Hold and drag to move the cursor. Up and down move between explicit lines.")
  }

  private static let activationDelay: TimeInterval = 0.22
  private static let pointsPerCharacter: CGFloat = 7.5
  private static let pointsPerLine: CGFloat = 25
  private static let minimumMovement: CGFloat = 2

  @State private var isPressed = false
  @State private var isTrackpadActive = false
  @State private var pressStartTime: Date?
  @State private var activationTask: Task<Void, Never>?
  @State private var lastReportedCharOffset = 0
  @State private var lastReportedLineOffset = 0

  @ViewBuilder
  private var label: some View {
    if self.useCustomSpaceBar {
      SayboardWordmark()
        .fill(.primary)
        .opacity(self.isTrackpadActive ? 0.05 : 0.2)
        .frame(height: 21.36.kbScaled)
    } else {
      Color.clear
    }
  }

  private func beginPress(at time: Date) {
    self.pressStartTime = time
    self.isPressed = true
    KeyboardHaptics.key()
    self.activationTask?.cancel()
    self.activationTask = Task { @MainActor in
      try? await Task.sleep(for: .milliseconds(220))
      guard !Task.isCancelled, self.isPressed else { return }
      self.activateTrackpad()
    }
  }

  private func activateTrackpad() {
    guard !self.isTrackpadActive else { return }
    self.isTrackpadActive = true
    self.onTrackingBegan?()
    self.lastReportedCharOffset = 0
    self.lastReportedLineOffset = 0
    KeyboardHaptics.key(strength: 0.75)
  }

  private func handleDragChanged(_ value: DragGesture.Value) {
    if self.pressStartTime == nil {
      self.beginPress(at: value.time)
    }

    guard let startTime = self.pressStartTime else { return }
    let elapsed = value.time.timeIntervalSince(startTime)
    if !self.isTrackpadActive,
       elapsed >= Self.activationDelay,
       max(abs(value.translation.width), abs(value.translation.height)) > Self.minimumMovement {
      self.activateTrackpad()
    }
    guard self.isTrackpadActive else { return }

    // The spacebar owns this gesture even when the finger moves over the
    // dimmed letter rows: no second recognizer or printable key is invoked.
    let horizontal = Int(value.translation.width / Self.pointsPerCharacter)
    let delta = horizontal - self.lastReportedCharOffset
    if delta != 0 {
      self.onCursorMove(delta)
      self.lastReportedCharOffset = horizontal
    }
    let vertical = Int(value.translation.height / Self.pointsPerLine)
    let lineDelta = vertical - self.lastReportedLineOffset
    if lineDelta != 0 {
      self.onVerticalCursorMove?(lineDelta)
      self.lastReportedLineOffset = vertical
    }
  }

  private func handleDragEnded() {
    self.finishTracking(emitSpace: true)
  }

  private func finishTracking(emitSpace: Bool) {
    let wasTracking = self.isTrackpadActive
    self.activationTask?.cancel()
    self.activationTask = nil
    if emitSpace && self.isPressed && !wasTracking {
      KeyboardInputTrace.record(.spaceTouched)
      self.onSpace()
    }
    self.isPressed = false
    self.isTrackpadActive = false
    self.pressStartTime = nil
    self.lastReportedCharOffset = 0
    self.lastReportedLineOffset = 0
    if wasTracking { self.onTrackingEnded?() }
  }
}
