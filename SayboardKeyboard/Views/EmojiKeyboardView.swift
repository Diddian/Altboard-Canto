import SwiftUI

/// Keyboard-extension emoji browser: offline full RGI catalogue and an
/// in-extension search keypad (a TextField cannot summon iOS's own emoji UI).
struct EmojiKeyboardView: View {
  let proxy: KeyboardProxy
  @ObservedObject var keyboardState: KeyboardState

  @State private var search = ""
  @State private var searchActive = false
  @State private var selectedGroup = "All"

  private let columns = Array(repeating: GridItem(.flexible(), spacing: 3), count: 8)

  private var filteredEntries: [EmojiCatalogEntry] {
    let query = self.search.trimmingCharacters(in: .whitespacesAndNewlines)
    let english = Self.searchAliases[query] ?? query
    return EmojiCatalog.entries.filter { entry in
      if !query.isEmpty {
        return entry.name.localizedCaseInsensitiveContains(english)
          || entry.emoji.contains(query)
      }
      return self.selectedGroup == "All" || entry.group == self.selectedGroup
    }
  }

  var body: some View {
    VStack(spacing: 3) {
      HStack(spacing: 5) {
        Button {
          self.searchActive = true
        } label: {
          HStack(spacing: 6) {
            Image(systemName: "magnifyingglass")
            Text(self.search.isEmpty ? "Search Emoji" : self.search)
              .lineLimit(1)
              .frame(maxWidth: .infinity, alignment: .leading)
          }
          .font(.system(size: 14.kbScaled))
          .foregroundStyle(.secondary)
          .padding(.horizontal, 9.kbScaled)
          .frame(height: 31.kbScaled)
          .background(Color(uiColor: KeyboardPalette.keyFill),
                      in: RoundedRectangle(cornerRadius: 8.kbScaled))
        }
        .buttonStyle(.plain)

        if self.searchActive {
          if !self.search.isEmpty {
            Button {
              self.search = ""
            } label: {
              Image(systemName: "xmark.circle.fill")
                .frame(width: 25.kbScaled, height: 31.kbScaled)
            }
            .buttonStyle(.plain)
          }
          Button("Done") { self.searchActive = false }
            .font(.system(size: 13.kbScaled, weight: .medium))
        } else {
          RepeatDeleteButton(proxy: self.proxy, fixedWidth: 47.kbScaled)
        }
      }
      .padding(.horizontal, 6.kbScaled)
      .frame(height: 34.kbScaled)

      ScrollView(.horizontal) {
        HStack(spacing: 5) {
          ForEach(["All"] + EmojiCatalog.groups, id: \.self) { group in
            Button {
              self.selectedGroup = group
              self.searchActive = false
              self.search = ""
            } label: {
              Text(group)
                .font(.system(size: 11.kbScaled, weight: self.selectedGroup == group ? .semibold : .regular))
                .lineLimit(1)
                .padding(.horizontal, 8.kbScaled)
                .frame(height: 23.kbScaled)
                .background(
                  self.selectedGroup == group
                    ? Color(uiColor: KeyboardPalette.pressedFill)
                    : Color(uiColor: KeyboardPalette.keyFill),
                  in: Capsule()
                )
            }
            .buttonStyle(.plain)
          }
        }
        .padding(.horizontal, 6.kbScaled)
      }
      .scrollIndicators(.hidden)
      .frame(height: 24.kbScaled)

      ScrollView {
        LazyVGrid(columns: self.columns, spacing: 7.kbScaled) {
          ForEach(self.filteredEntries) { entry in
            Button {
              self.proxy.insertText(entry.emoji)
            } label: {
              Text(entry.emoji)
                .font(.system(size: 26.kbScaled))
                .frame(maxWidth: .infinity, minHeight: 32.kbScaled)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(entry.name)
          }
        }
        .padding(.horizontal, 6.kbScaled)
      }

      if self.searchActive { self.searchKeypad }

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
    .frame(height: KeyboardMetrics.totalHeight(
      actionBarVisible: false, kind: self.keyboardState.keyboardKind
    ))
  }

  private var searchKeypad: some View {
    VStack(spacing: 2.kbScaled) {
      self.searchRow("qwertyuiop")
      self.searchRow("asdfghjkl")
      HStack(spacing: 3.kbScaled) {
        self.searchRow("zxcvbnm")
        Button {
          if !self.search.isEmpty { self.search.removeLast() }
        } label: {
          Image(systemName: "delete.left")
            .font(.system(size: 16.kbScaled))
            .frame(width: 39.kbScaled, height: 28.kbScaled)
            .background(Color(uiColor: KeyboardPalette.keyFill),
                        in: RoundedRectangle(cornerRadius: 5.kbScaled))
        }
        .buttonStyle(.plain)
      }
    }
  }

  private func searchRow(_ letters: String) -> some View {
    HStack(spacing: 3.kbScaled) {
      ForEach(Array(letters).map(String.init), id: \.self) { letter in
        Button {
          self.search.append(letter)
        } label: {
          Text(letter)
            .font(.system(size: 14.kbScaled))
            .frame(maxWidth: .infinity)
            .frame(height: 28.kbScaled)
            .background(Color(uiColor: KeyboardPalette.keyFill),
                        in: RoundedRectangle(cornerRadius: 5.kbScaled))
        }
        .buttonStyle(.plain)
      }
    }
    .frame(maxWidth: .infinity)
    .padding(.horizontal, 4.kbScaled)
  }

  private static let searchAliases: [String: String] = [
    "笑": "smile", "心": "heart", "愛": "love", "貓": "cat",
    "狗": "dog", "花": "flower", "食": "food", "旗": "flag",
    "手": "hand", "火": "fire", "香港": "Hong Kong"
  ]
}
