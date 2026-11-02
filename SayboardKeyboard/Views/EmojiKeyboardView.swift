import SwiftUI

struct EmojiKeyboardView: View {
  let proxy: KeyboardProxy
  @ObservedObject var keyboardState: KeyboardState
  @State private var search = ""

  private static let groups: [(String, String)] = [
    ("Faces", "😀 😃 😄 😁 😆 😅 😂 🤣 🥲 😊 🙂 🙃 😉 😍 🥰 😘 😋 😛 😜 🤪 🤔 🫡 🤨 😐 😑 😶 🙄 😏 😔 😢 😭 😤 😡 🤯 😱 🥹 🥺 😴 🤗"),
    ("Gestures", "👍 👎 👌 🤌 🤏 ✌️ 🤞 🫰 🤟 🤘 🤙 👋 🤚 🖐️ ✋ 🫶 🙌 👏 🤝 🙏 💪 🫵 👀"),
    ("Hearts", "❤️ 🧡 💛 💚 💙 💜 🖤 🤍 🤎 💔 ❤️‍🔥 💕 💞 💓 💗 💖 💘 💝 💟"),
    ("Objects", "✅ ❌ ⚠️ 💯 🎉 🎊 🎁 🎂 🎵 🎶 🔥 ✨ ⭐ 🌟 💡 📌 📍 📅 📝 ✉️ 📩 📱 💻 ☕ 🍵 🍕 🍜 🥐"),
    ("Nature", "🌸 🌹 🌺 🌻 🌷 🌱 🌲 🌳 🍀 🍁 🍂 🌞 🌝 🌛 🌧️ 🌈 ❄️ ☁️ 🌍 🐱 🐶 🐼 🐦 🦋")
  ]

  private let columns = Array(repeating: GridItem(.flexible(), spacing: 3), count: 8)

  var body: some View {
    VStack(spacing: 5) {
      HStack {
        Text("Emoji").font(.subheadline.weight(.semibold))
        Spacer()
        RepeatDeleteButton(proxy: self.proxy, fixedWidth: 50.kbScaled)
      }
      .padding(.horizontal, 6.kbScaled)
      .frame(height: KeyboardChromeMetrics.keyHeight)

      ScrollView {
        LazyVGrid(columns: self.columns, spacing: 7) {
          ForEach(Self.groups.indices, id: \.self) { index in
            ForEach(Self.groups[index].1.split(separator: " ").map(String.init), id: \.self) { symbol in
              Button {
                self.proxy.insertText(symbol)
              } label: {
                Text(symbol).font(.system(size: 27.kbScaled))
                  .frame(maxWidth: .infinity, minHeight: 33.kbScaled)
              }
              .buttonStyle(.plain)
            }
          }
        }
        .padding(.horizontal, 6)
      }

      KeyboardBottomRow(
        proxy: self.proxy,
        metrics: KeyboardChromeMetrics(keyboardState: self.keyboardState),
        keyboardState: self.keyboardState,
        alphabeticModeLabel: "ABC",
        onAlphabeticModeSwitch: {
          self.keyboardState.showsEmojiPicker = false
          self.keyboardState.keyboardKind = .alphabetic
          SharedSettings().keyboardKind = .alphabetic
          self.proxy.setActionBarVisible(false)
        },
        showsAlphabetIndicator: false,
        onSpaceAction: { self.proxy.insertSpace() },
        onReturnAction: { self.proxy.insertText("\n") }
      )
    }
    .frame(height: KeyboardMetrics.totalHeight(actionBarVisible: false, kind: self.keyboardState.keyboardKind))
  }
}
