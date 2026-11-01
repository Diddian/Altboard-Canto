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
    if kind == .extended {
      return max(284, 289.5 * CGFloat(heightFactor))
    }
    let factor = CGFloat(heightFactor)
    return factor < 0.90
      ? 150 + (factor - 0.70) * 420
      : 260 * factor
  }

  var body: some View {
    GeometryReader { geo in
      let gap: CGFloat = 6
      let rowsHeight: CGFloat = self.compact ? 96 : 198
      let inset = self.compact
        ? max(0, (geo.size.height - rowsHeight) / 2)
        : max(0, geo.size.height - rowsHeight - 4)

      VStack(spacing: gap) {
        if self.kind == .standard {
          if !self.compact {
            Image(systemName: "mic.fill")
              .font(.system(size: 29))
              .frame(width: 96, height: 96)
              .background(Color(.tertiarySystemFill),
                in: RoundedRectangle(cornerRadius: 48))
              .frame(maxWidth: .infinity)
          }
          self.standardControls(compact: self.compact)
        } else {
          self.standardControls(compact: true)
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
        self.spaceRow
      }
      .padding(.top, self.kind == .standard ? inset : 0)
      .frame(maxWidth: .infinity, alignment: .top)
    }
    .frame(height: self.previewHeight)
    .padding(.horizontal, 4)
    .background(Color(.secondarySystemGroupedBackground),
      in: RoundedRectangle(cornerRadius: 14))
    .animation(.easeInOut(duration: 0.15), value: self.heightFactor)
    .accessibilityLabel("Preview of keyboard: every key keeps the same size")
  }

  private func standardControls(compact: Bool) -> some View {
    HStack(spacing: 6) {
      self.key("gearshape")
      self.key("character.bubble")
      if compact {
        Image(systemName: "mic.fill")
          .font(.system(size: 21))
          .frame(maxWidth: .infinity)
          .frame(height: 45)
          .background(Color(.tertiarySystemFill),
            in: RoundedRectangle(cornerRadius: 8.5))
      } else {
        Spacer(minLength: 0)
      }
      self.key("sparkles")
      self.key("delete.left")
    }
    .frame(height: 45)
  }

  private var spaceRow: some View {
    HStack(spacing: 6) {
      self.key("face.smiling")
      self.key("trash")
      Image(systemName: "space")
        .font(.system(size: 18))
        .frame(maxWidth: .infinity)
        .frame(height: 45)
        .background(Color(.tertiarySystemFill),
          in: RoundedRectangle(cornerRadius: 8.5))
      self.key("return.left", width: 96)
    }
    .frame(height: 45)
  }

  private func key(_ name: String, width: CGFloat = 45) -> some View {
    Image(systemName: name)
      .font(.system(size: 18))
      .frame(width: width, height: 45)
      .background(Color(.tertiarySystemFill),
        in: RoundedRectangle(cornerRadius: 8.5))
  }
}
