import SwiftUI

struct KeyboardSettingsView: View {

  @Binding var selectedKind: KeyboardKind

  var body: some View {
    Form {
      Section {
        Picker("Keyboard Type", selection: self.$selectedKind) {
          ForEach(KeyboardKind.allCases, id: \.self) { kind in
            Text(LocalizedStringKey(kind.displayNameKey)).tag(kind)
          }
        }
        Toggle("Haptic Feedback", isOn: self.$keyboardHapticsEnabled)
        VStack(alignment: .leading, spacing: 12) {
          HStack {
            Text("Keyboard height")
            Spacer()
            Text("\(Int(self.heightScale * 100))%")
              .foregroundStyle(.secondary)
              .monospacedDigit()
          }
          Slider(value: self.$heightScale, in: 0.70...1.10, step: 0.02)
            .accessibilityLabel("Keyboard height")
          KeyboardHeightPreview(kind: self.selectedKind, heightFactor: self.heightScale)
          Text(self.heightScale < 0.82
            ? "Compact layout: microphone becomes a wide pill above the space bar."
            : "Standard layout: round microphone and thumb-friendly controls.")
            .font(.footnote)
            .foregroundStyle(.secondary)
          Button("Reset to recommended height") { self.heightScale = 0.92 }
            .font(.footnote)
        }
      } footer: {
        Text("The duplicate globe key is now Emoji. Long-press Emoji to switch keyboards where required.")
      }
      Section {
        Toggle("“.” Shortcut", isOn: self.$periodShortcutEnabled)
      } footer: {
        Text("Double tapping the space bar will insert a period followed by a space.")
      }
    }
    .navigationTitle("Keyboard")
    .navigationBarTitleDisplayMode(.inline)
  }

  @AppStorage(SharedKey.keyboardHapticsEnabled, store: UserDefaults(suiteName: AppGroup.identifier))
  private var keyboardHapticsEnabled = true
  @AppStorage(SharedKey.periodShortcutEnabled, store: UserDefaults(suiteName: AppGroup.identifier))
  private var periodShortcutEnabled = true
  @AppStorage(SharedKey.keyboardHeightScale, store: UserDefaults(suiteName: AppGroup.identifier))
  private var heightScale = 0.92
}


private struct KeyboardHeightPreview: View {
  let kind: KeyboardKind
  let heightFactor: Double

  private var compact: Bool { kind == .standard && heightFactor < 0.82 }
  private var factor: CGFloat { CGFloat(heightFactor) }

  var body: some View {
    VStack(spacing: 8 * factor) {
      if kind == .standard {
        HStack(alignment: .bottom) {
          Image(systemName: "gearshape")
            .frame(width: 44 * factor, height: 42 * factor)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 9))
          Spacer()
          Image(systemName: "mic.fill")
            .font(.system(size: 26 * factor))
            .frame(
              width: (compact ? 156 : 106) * factor,
              height: (compact ? 56 : 106) * factor
            )
            .background(.regularMaterial,
              in: RoundedRectangle(cornerRadius: (compact ? 28 : 53) * factor))
          Spacer()
          Image(systemName: "delete.left")
            .frame(width: 44 * factor, height: 42 * factor)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 9))
        }
      } else {
        HStack {
          Image(systemName: "gearshape")
          Spacer()
          Image(systemName: "mic.fill")
            .frame(width: 104 * factor, height: 46 * factor)
            .background(.regularMaterial, in: Capsule())
        }
        .font(.system(size: 19 * factor))
      }
      HStack(spacing: 6 * factor) {
        Image(systemName: "face.smiling")
          .frame(width: 42 * factor)
        Image(systemName: "trash")
          .frame(width: 42 * factor)
        Text("space")
          .frame(maxWidth: .infinity)
        Image(systemName: "return.left")
          .frame(width: 65 * factor)
      }
      .font(.system(size: 15 * factor))
      .frame(height: 43 * factor)
      .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 9))
    }
    .padding(12 * factor)
    .frame(maxWidth: .infinity)
    .frame(height: (compact ? 160 : kind == .standard ? 222 : 185) * factor)
    .background(Color(.secondarySystemGroupedBackground),
      in: RoundedRectangle(cornerRadius: 14))
    .animation(.easeInOut(duration: 0.15), value: self.heightFactor)
    .accessibilityLabel("Preview of the keyboard height and microphone layout")
  }
}
