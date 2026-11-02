import SwiftUI

/// A horizontal, category-paged emoji keyboard. No Genmoji, no redundant
/// emoji-mode button, and no second touch/gesture layer over the grid.
struct EmojiKeyboardView: View {
  let proxy: KeyboardProxy
  @ObservedObject var keyboardState: KeyboardState

  @State private var search = ""
  @State private var searchActive = false
  @State private var selectedGroup = "Smileys & Emotion"
  @State private var currentPage: Int? = 1
  @State private var frequent = [EmojiCatalogEntry]()

  private let pageSize = 32
  private let columns = Array(repeating: GridItem(.flexible(), spacing: 0), count: 8)

  private struct Page: Identifiable {
    let id: Int
    let group: String
    let emojis: [EmojiCatalogEntry]
  }

  private var displayedPages: [Page] {
    var result = [Page]()
    func append(_ group: String, items: [EmojiCatalogEntry]) {
      if items.isEmpty {
        result.append(Page(id: result.count, group: group, emojis: []))
        return
      }
      for offset in stride(from: 0, to: items.count, by: pageSize) {
        result.append(Page(
          id: result.count, group: group,
          emojis: Array(items.dropFirst(offset).prefix(pageSize))
        ))
      }
    }

    let query = self.search.trimmingCharacters(in: .whitespacesAndNewlines)
    if !query.isEmpty {
      let alias = Self.searchAliases[query] ?? query
      let entries = EmojiCatalog.entries.filter {
        $0.name.localizedCaseInsensitiveContains(alias) || $0.emoji.contains(query)
      }
      append("Search", items: entries)
    } else {
      append("Frequently Used", items: self.frequent)
      for group in EmojiCatalog.groups {
        append(group, items: EmojiCatalog.entries.filter { $0.group == group })
      }
    }
    return result
  }

  var body: some View {
    VStack(spacing: 0) {
      self.searchHeader
        .frame(height: 52.kbScaled)
      GeometryReader { geometry in
        let pages = self.displayedPages
        ScrollView(.horizontal) {
          LazyHStack(spacing: 0) {
            ForEach(pages) { page in
              self.emojiPage(page, width: geometry.size.width, height: geometry.size.height)
                .id(page.id)
            }
          }
          .scrollTargetLayout()
        }
        .scrollTargetBehavior(.paging)
        .scrollPosition(id: self.$currentPage)
        .scrollIndicators(.hidden)
        .onChange(of: self.currentPage) { _, index in
          if let index, index >= 0, index < pages.count {
            self.selectedGroup = pages[index].group
          }
        }
      }

      if self.searchActive {
        self.searchKeypad
          .frame(height: 87.kbScaled)
      }

      self.categoryRail
        .frame(height: 47.kbScaled)
    }
    .frame(height: KeyboardMetrics.emojiHeight)
    .background(Color(red: 31 / 255, green: 31 / 255, blue: 31 / 255))
    .onAppear {
      self.frequent = EmojiHistory.mostUsed()
      if !self.frequent.isEmpty {
        self.currentPage = 0
        self.selectedGroup = "Frequently Used"
      } else {
        self.currentPage = 1
        self.selectedGroup = EmojiCatalog.groups.first ?? "Smileys & Emotion"
      }
    }
  }

  private var searchHeader: some View {
    HStack(spacing: 7.kbScaled) {
      Button {
        self.searchActive = true
        if self.search.isEmpty { self.currentPage = 0 }
      } label: {
        HStack(spacing: 11.kbScaled) {
          Image(systemName: "magnifyingglass")
            .font(.system(size: 19.kbScaled, weight: .regular))
            .foregroundStyle(.secondary)
          Text(self.search.isEmpty ? "Search Emoji" : self.search)
            .font(.system(size: 18.kbScaled))
            .foregroundStyle(self.search.isEmpty ? .secondary : .primary)
            .lineLimit(1)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, 13.kbScaled)
        .frame(height: 40.kbScaled)
        .background(Color(uiColor: KeyboardPalette.keyFill),
                    in: Capsule())
      }
      .buttonStyle(.plain)
      .accessibilityLabel("Search emoji")

      if self.searchActive {
        if !self.search.isEmpty {
          Button {
            self.search = ""
            self.currentPage = 1
          } label: {
            Image(systemName: "xmark.circle.fill")
              .font(.system(size: 18.kbScaled))
          }
          .accessibilityLabel("Clear emoji search")
          .buttonStyle(.plain)
        }
        Button("Done") {
          self.searchActive = false
          self.search = ""
          self.goToGroup("Smileys & Emotion")
        }
        .font(.system(size: 14.kbScaled, weight: .medium))
        .buttonStyle(.plain)
      }
    }
    .padding(.horizontal, 9.kbScaled)
  }

  private func emojiPage(_ page: Page, width: CGFloat, height: CGFloat) -> some View {
    Group {
      if page.emojis.isEmpty {
        VStack {
          Spacer()
          Text(page.group == "Frequently Used"
               ? "Your most used emoji will appear here." : "No matching emoji")
            .font(.system(size: 13.kbScaled))
            .foregroundStyle(.secondary)
          Spacer()
        }
      } else {
        LazyVGrid(columns: self.columns, spacing: 0) {
          ForEach(page.emojis) { entry in
            Button {
              self.proxy.insertText(entry.emoji)
              EmojiHistory.remember(entry.emoji)
              self.frequent = EmojiHistory.mostUsed()
            } label: {
              Text(entry.emoji)
                .font(.system(size: 33.kbScaled))
                .frame(maxWidth: .infinity)
                .frame(height: 55.5.kbScaled)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(entry.name)
          }
        }
        .padding(.top, 4.kbScaled)
        .offset(x: 11.kbScaled)
        .frame(maxHeight: .infinity, alignment: .top)
      }
    }
    .frame(width: width, height: height)
  }

  private var categoryRail: some View {
    HStack(spacing: 0) {
      Button {
        self.searchActive = false
        self.search = ""
        self.keyboardState.showsEmojiPicker = false
        self.keyboardState.keyboardKind = .alphabetic
        SharedSettings().keyboardKind = .alphabetic
        self.proxy.setActionBarVisible(false)
      } label: {
        Text("ABC")
          .font(.system(size: 19.kbScaled, weight: .regular))
          .frame(width: 57.kbScaled, height: 44.kbScaled)
      }
      .buttonStyle(.plain)
      .accessibilityLabel("Return to alphabet keyboard")

      ForEach(["Frequently Used"] + EmojiCatalog.groups, id: \.self) { group in
        Button {
          self.goToGroup(group)
        } label: {
          Image(systemName: Self.icon(for: group))
            .font(.system(size: 18.kbScaled))
            .foregroundStyle(self.selectedGroup == group ? .primary : .secondary)
            .frame(maxWidth: .infinity)
            .frame(height: 42.kbScaled)
            .background {
              if self.selectedGroup == group {
                Circle().fill(Color(uiColor: KeyboardPalette.keyFill))
              }
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(group)
        .accessibilityAddTraits(self.selectedGroup == group ? .isSelected : [])
      }

      RepeatDeleteButton(
        proxy: self.proxy, fixedWidth: 45.kbScaled, nativeEmojiStyle: true
      )
    }
    .padding(.horizontal, 3.kbScaled)
    .offset(y: -5.kbScaled)
  }

  private func goToGroup(_ group: String) {
    self.searchActive = false
    self.search = ""
    self.selectedGroup = group
    self.currentPage = self.displayedPages.firstIndex { $0.group == group } ?? 0
  }

  private var searchKeypad: some View {
    VStack(spacing: 2.kbScaled) {
      self.searchRow("qwertyuiop")
      self.searchRow("asdfghjkl")
      HStack(spacing: 3.kbScaled) {
        self.searchRow("zxcvbnm")
        Button {
          if !self.search.isEmpty { self.search.removeLast() }
          self.currentPage = 0
        } label: {
          Image(systemName: "delete.left")
            .font(.system(size: 16.kbScaled))
            .frame(width: 39.kbScaled, height: 27.kbScaled)
            .background(Color(uiColor: KeyboardPalette.keyFill),
                        in: RoundedRectangle(cornerRadius: 5.kbScaled))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Delete search character")
      }
    }
  }

  private func searchRow(_ letters: String) -> some View {
    HStack(spacing: 3.kbScaled) {
      ForEach(Array(letters).map(String.init), id: \.self) { letter in
        Button {
          self.search.append(letter)
          self.currentPage = 0
        } label: {
          Text(letter)
            .font(.system(size: 14.kbScaled))
            .frame(maxWidth: .infinity)
            .frame(height: 27.kbScaled)
            .background(Color(uiColor: KeyboardPalette.keyFill),
                        in: RoundedRectangle(cornerRadius: 5.kbScaled))
        }
        .buttonStyle(.plain)
      }
    }
    .frame(maxWidth: .infinity)
    .padding(.horizontal, 4.kbScaled)
  }

  private static func icon(for group: String) -> String {
    switch group {
    case "Frequently Used": "clock"
    case "Smileys & Emotion": "face.smiling"
    case "People & Body": "person.2"
    case "Animals & Nature": "pawprint"
    case "Food & Drink": "carrot"
    case "Travel & Places": "car"
    case "Activities": "soccerball"
    case "Objects": "lightbulb"
    case "Symbols": "heart"
    case "Flags": "flag"
    default: "circle.grid.2x2"
    }
  }

  private static let searchAliases: [String: String] = [
    "笑": "smile", "心": "heart", "愛": "love", "貓": "cat",
    "狗": "dog", "花": "flower", "食": "food", "旗": "flag",
    "手": "hand", "火": "fire", "香港": "Hong Kong"
  ]
}
