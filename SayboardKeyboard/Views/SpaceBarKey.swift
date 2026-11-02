import SwiftUI

struct SpaceBarKey: View {

  let useCustomSpaceBar: Bool
  let showsAlphabetIndicator: Bool
  let onSpace: () -> Void
  let onCursorMove: (Int) -> Void
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
  }

  private static let activationDelay: TimeInterval = 0.15
  private static let pointsPerCharacter: CGFloat = 7.5
  private static let verticalDeadZone: CGFloat = 50
  private static let minimumHorizontalMovement: CGFloat = 2

  @State private var isPressed = false
  @State private var isTrackpadActive = false
  @State private var pressStartTime: Date?
  @State private var lastReportedCharOffset = 0

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

  private func handleDragChanged(_ value: DragGesture.Value) {
    if self.pressStartTime == nil {
      self.pressStartTime = value.time
      self.isPressed = true
      KeyboardHaptics.key()
    }

    guard let startTime = self.pressStartTime else { return }
    let elapsed = value.time.timeIntervalSince(startTime)

    if self.isTrackpadActive {
      guard abs(value.translation.height) < Self.verticalDeadZone else { return }

      let totalOffset = value.translation.width / Self.pointsPerCharacter
      let charOffset = Int(totalOffset)
      let delta = charOffset - self.lastReportedCharOffset

      if delta != 0 {
        self.onCursorMove(delta)
        self.lastReportedCharOffset = charOffset
      }
    } else if
      elapsed >= Self.activationDelay,
      abs(value.translation.width) > Self.minimumHorizontalMovement
    {
      self.isTrackpadActive = true
      self.onTrackingBegan?()
      self.lastReportedCharOffset = 0
      KeyboardHaptics.key(strength: 0.75)
    }
  }

  private func handleDragEnded() {
    let wasTracking = self.isTrackpadActive
    if !self.isTrackpadActive {
      KeyboardInputTrace.record(.spaceTouched)
      self.onSpace()
    }

    self.isPressed = false
    self.isTrackpadActive = false
    self.pressStartTime = nil
    self.lastReportedCharOffset = 0
    if wasTracking { self.onTrackingEnded?() }
  }
}
