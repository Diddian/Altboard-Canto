import SwiftUI

/// Compact, offline Emoji picker replacing only the three alphabet rows.
/// Search uses an inline keypad so iOS never opens a nested keyboard.
struct EmojiKeyboardView: View {
  let proxy: KeyboardProxy
  @ObservedObject var keyboardState: KeyboardState
  let onAlphabet: () -> Void
  let onNumbers: () -> Void

  @State private var search = ""
  @State private var searchActive = false
  @State private var selectedGroup = "Recent"
  @State private var recent = EmojiCatalog.common

  private static let columns = Array(
    repeating: GridItem(.flexible(), spacing: 0), count: 8
  )
  private static let categories: [(name: String, icon: String)] = [
    ("Recent", "clock"),
    ("Smileys & Emotion", "face.smiling"),
    ("People & Body", "person.2"),
    ("Animals & Nature", "pawprint"),
    ("Food & Drink", "fork.knife"),
    ("Travel & Places", "car"),
    ("Activities", "sportscourt"),
    ("Objects", "lightbulb"),
    ("Symbols", "heart"),
    ("Flags", "flag")
  ]

  private var entries: [EmojiCatalogEntry] {
    if !self.search.isEmpty {
      return EmojiCatalog.search(self.search, group: nil)
    }
    if self.selectedGroup == "Recent" {
      return self.recent.map {
        EmojiCatalogEntry(group: "Recent", name: $0, emoji: $0)
      }
    }
    return EmojiCatalog.search("", group: self.selectedGroup)
  }

  var body: some View {
    VStack(spacing: 0) {
      self.searchToolbar
        .padding(.top, KeyboardLayoutGeometry.alphabetToolbarTopInset.kbScaled)
        .padding(.bottom, KeyboardLayoutGeometry.alphabetToolbarBottomInset.kbScaled)

      Group {
        if self.searchActive {
          self.searchKeypad
        } else {
          ScrollView(.vertical) {
            LazyVGrid(columns: Self.columns,
                      spacing: KeyboardLayoutGeometry.alphabetRowSpacing.kbScaled) {
              ForEach(self.entries) { item in
                Button {
                  KeyboardHaptics.key()
                  self.proxy.insertText(item.emoji)
                  self.recent = EmojiCatalog.remember(item.emoji)
                } label: {
                  Text(verbatim: item.emoji)
                    .font(.system(size: 28.kbScaled))
                    .frame(maxWidth: .infinity)
                    .frame(height: KeyboardChromeMetrics.keyHeight)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(item.name)
              }
            }
            .padding(.horizontal, 5.kbScaled)
          }
          .scrollIndicators(.hidden)
        }
      }
      .frame(height: 3 * KeyboardChromeMetrics.keyHeight
        + 2 * KeyboardLayoutGeometry.alphabetRowSpacing.kbScaled)

      self.bottomRow
        .padding(.top, KeyboardLayoutGeometry.alphabetRowSpacing.kbScaled)
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    .onAppear { self.recent = EmojiCatalog.recent() }
  }

  private var searchToolbar: some View {
    HStack(spacing: 7.kbScaled) {
      NativeInputModeSwitchKey(
        configure: self.keyboardState.configureInputModeListButton
      )
      .frame(width: 30.kbScaled, height: KeyboardChromeMetrics.keyHeight)
      Button {
        self.searchActive = true
      } label: {
        HStack(spacing: 6.kbScaled) {
          Image(systemName: "magnifyingglass")
          Text(verbatim: self.search.isEmpty ? "Search Emoji" : self.search)
            .lineLimit(1)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .font(.system(size: 16.kbScaled))
        .foregroundStyle(.secondary)
        .padding(.horizontal, 12.kbScaled)
        .frame(height: KeyboardChromeMetrics.keyHeight)
        .background(
          Color(uiColor: KeyboardPalette.keyFill).opacity(0.8),
          in: RoundedRectangle(cornerRadius: 12.kbScaled)
        )
      }
      .buttonStyle(.plain)
      Button {
        self.search = ""
        self.searchActive = false
      } label: {
        Image(systemName: "xmark")
          .font(.system(size: 16.kbScaled, weight: .semibold))
          .frame(width: 35.kbScaled, height: KeyboardChromeMetrics.keyHeight)
          .contentShape(Rectangle())
      }
      .buttonStyle(.plain)
      .accessibilityLabel("Clear Emoji search")
    }
    .padding(.horizontal, KeyboardLayoutGeometry.alphabetEdgeInset.kbScaled)
    .frame(height: KeyboardChromeMetrics.keyHeight)
  }

  private var searchKeypad: some View {
    let arrangement = SharedSettings().keyboardLetterArrangement
    return VStack(spacing: KeyboardLayoutGeometry.alphabetRowSpacing.kbScaled) {
      self.searchRow(arrangement.rows[0])
      self.searchRow(arrangement.rows[1])
        .padding(.horizontal, 18.kbScaled)
      HStack(spacing: 6.kbScaled) {
        self.searchRow(arrangement.rows[2])
        KeyButton(content: .systemImage("delete.left"), fixedWidth: 48.kbScaled) {
          if !self.search.isEmpty { self.search.removeLast() }
        }
      }
    }
    .padding(.horizontal, KeyboardLayoutGeometry.alphabetEdgeInset.kbScaled)
  }

  private func searchRow(_ letters: [String]) -> some View {
    HStack(spacing: KeyboardChromeMetrics.buttonSpacing) {
      ForEach(letters, id: \.self) { letter in
        KeyButton(content: .symbol(letter.lowercased(), fontSize: 17)) {
          self.search += letter.lowercased()
        }
      }
    }
    .frame(height: KeyboardChromeMetrics.keyHeight)
  }

  private var bottomRow: some View {
    HStack(spacing: KeyboardChromeMetrics.buttonSpacing) {
      KeyButton(content: .symbol("ABC", fontSize: 16), fixedWidth: 50.kbScaled) {
        self.onAlphabet()
      }
      KeyButton(content: .symbol("123", fontSize: 16), fixedWidth: 48.kbScaled) {
        self.onNumbers()
      }

      ScrollView(.horizontal) {
        HStack(spacing: 10.kbScaled) {
          ForEach(Array(Self.categories.enumerated()), id: \.offset) { _, category in
            Button {
              self.selectedGroup = category.name
              self.search = ""
              self.searchActive = false
            } label: {
              Image(systemName: category.icon)
                .font(.system(size: 19.kbScaled, weight: .regular))
                .foregroundStyle(
                  self.selectedGroup == category.name ? Color.primary : Color.secondary
                )
                .frame(width: 27.kbScaled, height: KeyboardChromeMetrics.keyHeight)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(category.name)
          }
        }
      }
      .scrollIndicators(.hidden)

      KeyButton(content: .systemImage("delete.left"), fixedWidth: 46.kbScaled) {
        if self.searchActive {
          if !self.search.isEmpty { self.search.removeLast() }
        } else {
          self.proxy.deleteBackward()
        }
      }
      KeyButton(content: .systemImage("return.left"), fixedWidth: 48.kbScaled) {
        if self.searchActive {
          self.searchActive = false
        } else {
          self.proxy.insertText("\n")
        }
      }
    }
    .padding(.horizontal, KeyboardLayoutGeometry.alphabetSpecialRowInset.kbScaled)
    .padding(.bottom, 4.kbScaled)
  }
}
