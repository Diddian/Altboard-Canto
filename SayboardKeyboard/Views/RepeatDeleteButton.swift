import SwiftUI

/// A tap removes one character. Holding first repeats characters, then words.
/// The task is always cancelled on release or when the view disappears.
struct RepeatDeleteButton: View {
  let proxy: KeyboardProxy
  let fixedWidth: CGFloat
  /// Return true when a composition absorbed this delete.
  var onDeleteIntercept: (() -> Bool)? = nil
  /// Separate optional quick-tap interception. Hold behavior stays unchanged.
  var onTapDeleteIntercept: (() -> Bool)? = nil
  var onHostDeletion: (() -> Void)? = nil
  var fastCompositionRepeat = false
  /// Emoji category rail is icon-only, unlike the rectangular text keys.
  var nativeEmojiStyle = false

  @State private var deletionTask: Task<Void, Never>?
  @State private var didRepeat = false
  @State private var pressed = false

  var body: some View {
    Image(systemName: "delete.left")
      .font(.system(size: 19.25.kbScaled))
      .foregroundStyle(.primary)
      .frame(width: self.fixedWidth, height: 45.kbScaled)
      .background {
        if !self.nativeEmojiStyle {
          RoundedRectangle(cornerRadius: 8.5.kbScaled)
            .fill(Color(self.pressed ? .keyPressedBackground : .keyBackground))
        }
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
              try? await Task.sleep(for: .milliseconds(self.fastCompositionRepeat ? 310 : 420))
              guard !Task.isCancelled else { return }
              self.didRepeat = true
              // A held Delete is not evidence for adjacent-key touch correction.
              KeyboardTouchLearning.shared.invalidate()
              var repeats = 0
              while !Task.isCancelled {
                let intercepted = self.onDeleteIntercept?() ?? false
                if !intercepted {
                  if repeats < 24 {
                    self.proxy.deleteBackward()
                  } else {
                    if repeats == 24 { KeyboardHaptics.key(playsSound: false) }
                    self.proxy.deleteWordBackward()
                  }
                  self.onHostDeletion?()
                }
                repeats += 1
                try? await Task.sleep(for: .milliseconds(repeats < 24 ? 85 : 155))
              }
            }
          }
          .onEnded { _ in
            self.deletionTask?.cancel()
            self.deletionTask = nil
            if !self.didRepeat {
              // A verified just-swiped word is one undo unit on the first
              // Delete tap. Ordinary text still deletes one character.
              let intercepted = self.onTapDeleteIntercept?() ?? false
              if !intercepted {
                KeyboardTouchLearning.shared.recordDelete()
                self.proxy.deleteBackward()
              } else {
                KeyboardTouchLearning.shared.invalidate()
              }
              self.onHostDeletion?()
            }
            self.pressed = false
          }
      )
      .onDisappear {
        self.deletionTask?.cancel()
        self.deletionTask = nil
        self.didRepeat = false
        self.pressed = false
        KeyboardTouchLearning.shared.invalidate()
      }
      .accessibilityLabel("Delete; hold to delete characters, then words")
  }
}
