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
}
