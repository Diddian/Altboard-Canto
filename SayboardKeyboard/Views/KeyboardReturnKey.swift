import SwiftUI

/// Mirrors the host field's requested Return appearance. Text insertion is
/// still performed through the public text-document proxy.
struct KeyboardReturnKey: View {
  let appearance: KeyboardReturnAppearance
  let enabled: Bool
  let width: CGFloat
  let onPress: () -> Void

  var body: some View {
    Button {
      guard self.enabled else { return }
      KeyboardHaptics.key()
      self.onPress()
    } label: {
      Group {
        if let icon = self.appearance.icon {
          Image(systemName: icon)
            .font(.system(size: 21.kbScaled, weight: .medium))
        } else {
          Text(verbatim: self.appearance.title)
            .font(.system(size: 15.kbScaled, weight: .semibold))
            .lineLimit(1)
            .minimumScaleFactor(0.7)
        }
      }
      .frame(width: self.width, height: KeyboardChromeMetrics.keyHeight)
      .contentShape(Rectangle())
    }
    .buttonStyle(HostReturnStyle(prominent: self.appearance.prominent))
    .opacity(self.enabled ? 1 : 0.45)
    .accessibilityLabel(self.appearance.title)
    .accessibilityAddTraits(self.enabled ? [] : .isDisabled)
    .disabled(!self.enabled)
  }
}

private struct HostReturnStyle: ButtonStyle {
  let prominent: Bool

  func makeBody(configuration: Configuration) -> some View {
    configuration.label
      .foregroundStyle(self.prominent ? Color.white : Color.primary)
      .background(
        self.prominent
          ? Color(uiColor: .systemBlue).opacity(configuration.isPressed ? 0.75 : 1)
          : Color(uiColor: configuration.isPressed
              ? KeyboardPalette.pressedFill : KeyboardPalette.keyFill),
        in: RoundedRectangle(cornerRadius: 8.5.kbScaled, style: .continuous)
      )
  }
}
