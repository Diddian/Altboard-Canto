import SwiftUI

/// A tap removes one character. Holding first repeats characters, then words.
/// The task is always cancelled on release or when the view disappears.
struct RepeatDeleteButton: View {
  let proxy: KeyboardProxy
  let fixedWidth: CGFloat

  @State private var deletionTask: Task<Void, Never>?
  @State private var didRepeat = false
  @State private var pressed = false

  var body: some View {
    Image(systemName: "delete.left")
      .font(.system(size: 18.kbScaled))
      .foregroundStyle(.primary)
      .frame(width: self.fixedWidth, height: 45.kbScaled)
      .background {
        RoundedRectangle(cornerRadius: 8.5.kbScaled)
          .fill(Color(self.pressed ? .keyPressedBackground : .keyBackground))
      }
      .contentShape(Rectangle())
      .gesture(
        DragGesture(minimumDistance: 0)
          .onChanged { _ in
            guard !self.pressed else { return }
            self.pressed = true
            KeyboardHaptics.key()
            self.didRepeat = false
            self.deletionTask = Task { @MainActor in
              try? await Task.sleep(for: .milliseconds(420))
              guard !Task.isCancelled else { return }
              self.didRepeat = true
              var repeats = 0
              while !Task.isCancelled {
                if repeats < 24 {
                  self.proxy.deleteBackward()
                } else {
                  if repeats == 24 { KeyboardHaptics.key() }
                  self.proxy.deleteWordBackward()
                }
                repeats += 1
                try? await Task.sleep(for: .milliseconds(repeats < 24 ? 85 : 155))
              }
            }
          }
          .onEnded { _ in
            self.deletionTask?.cancel()
            self.deletionTask = nil
            if !self.didRepeat { self.proxy.deleteBackward() }
            self.pressed = false
          }
      )
      .onDisappear {
        self.deletionTask?.cancel()
        self.deletionTask = nil
      }
      .accessibilityLabel("Delete; hold to delete characters, then words")
  }
}
