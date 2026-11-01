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
        Button {
          self.keyboardState.showsEmojiPicker = false
        } label: {
          Label("ABC", systemImage: "keyboard")
            .font(.caption.weight(.semibold))
        }
        Spacer()
        Text("Emoji").font(.subheadline.weight(.semibold))
        Spacer()
        Button {
          self.proxy.deleteBackward()
        } label: {
          Image(systemName: "delete.left")
        }
      }
      .padding(.horizontal, 15)
      .frame(height: 35)

      ScrollView {
        LazyVGrid(columns: self.columns, spacing: 7) {
          ForEach(Array(Self.groups.enumerated()), id: \.offset) { _, group in
            ForEach(group.1.split(separator: " ").map(String.init), id: \.self) { symbol in
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
    }
    .frame(height: KeyboardMetrics.totalHeight(actionBarVisible: false, kind: self.keyboardState.keyboardKind))
  }
}
