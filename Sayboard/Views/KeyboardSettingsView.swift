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
          Text(self.heightScale < 0.90
            ? "Compact layout: a wide mic pill with one-line status."
            : "Round microphone. Only vertical whitespace changes; key sizes stay fixed.")
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

  private var compact: Bool { kind == .standard && heightFactor < 0.90 }
  private var previewHeight: CGFloat {
    let base: CGFloat = kind == .standard ? 240 : 289.5
    let minimum: CGFloat = kind == .standard ? (compact ? 158 : 216) : 284
    return max(minimum, base * CGFloat(heightFactor))
  }

  var body: some View {
    VStack(spacing: 6) {
      if kind == .standard {
        HStack {
          Spacer()
          Image(systemName: "mic.fill")
            .font(.system(size: compact ? 23 : 32))
            .frame(width: compact ? 205 : 106, height: compact ? 56 : 106)
            .background(Color(.tertiarySystemFill), in: RoundedRectangle(cornerRadius: compact ? 28 : 53))
          Spacer()
        }
        self.controlsRow
      } else {
        HStack {
          Image(systemName: "gearshape")
            .frame(width: 45, height: 45)
            .background(Color(.tertiarySystemFill), in: RoundedRectangle(cornerRadius: 9))
          Spacer()
          Image(systemName: "mic.fill")
            .frame(width: 100, height: 45)
            .background(Color(.tertiarySystemFill), in: Capsule())
        }
        ForEach(0..<3, id: \.self) { _ in
          HStack(spacing: 6) {
            ForEach(0..<8, id: \.self) { _ in
              RoundedRectangle(cornerRadius: 6)
                .fill(Color(.tertiarySystemFill))
                .frame(height: 45)
            }
          }
        }
      }
      HStack(spacing: 6) {
        Image(systemName: "face.smiling").frame(width: 45)
        Image(systemName: "trash").frame(width: 45)
        Image(systemName: "space").frame(maxWidth: .infinity)
        Image(systemName: "return.left").frame(width: 95)
      }
      .font(.system(size: 18))
      .frame(height: 45)
      .background(Color(.tertiarySystemFill), in: RoundedRectangle(cornerRadius: 9))
    }
    .padding(.top, 3)
    .padding(.horizontal, 4)
    .frame(maxWidth: .infinity, alignment: .top)
    .frame(height: self.previewHeight, alignment: .top)
    .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 14))
    .animation(.easeInOut(duration: 0.15), value: self.heightFactor)
    .accessibilityLabel("Keyboard height preview: key sizes remain unchanged")
  }

  private var controlsRow: some View {
    HStack(spacing: 6) {
      ForEach(["gearshape", "translate"], id: \.self) { name in
        Image(systemName: name)
          .frame(width: 45, height: 45)
          .background(Color(.tertiarySystemFill), in: RoundedRectangle(cornerRadius: 9))
      }
      Spacer()
      ForEach(["sparkles", "delete.left"], id: \.self) { name in
        Image(systemName: name)
          .frame(width: 45, height: 45)
          .background(Color(.tertiarySystemFill), in: RoundedRectangle(cornerRadius: 9))
      }
    }
  }
}
