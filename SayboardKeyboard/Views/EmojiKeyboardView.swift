import SwiftUI

/// The three alphabet rows become a fixed-height, horizontal Emoji browser.
/// Each page has eight columns and three rows; pages cross category boundaries.
struct EmojiKeyboardView: View {
  let proxy: KeyboardProxy
  @ObservedObject var keyboardState: KeyboardState
  let onAlphabet: () -> Void
  let onNumbers: () -> Void
  let onClose: () -> Void
  let onInsertEmoji: (String) -> Void

  @State private var search = ""
  @State private var searchActive = false
  @State private var selectedGroup = "Recent"
  @State private var recent = EmojiCatalog.common
  @State private var pageIndex: Int? = 0
  @State private var tonePickerCells = Set<String>()

  private let columns = Array(repeating: GridItem(.flexible(), spacing: 0), count: 8)
  private static let categories: [(name: String, icon: String)] = [
    ("Recent", "clock"), ("Smileys & Emotion", "face.smiling"),
    ("People & Body", "hand.raised"), ("Animals & Nature", "pawprint"),
    ("Food & Drink", "fork.knife"), ("Travel & Places", "car"),
    ("Activities", "sportscourt"), ("Objects", "lightbulb"),
    ("Symbols", "heart"), ("Flags", "flag")
  ]

  private var pages: [(group: String, entries: [EmojiCatalogEntry])] {
    if !self.search.isEmpty {
      let values = EmojiCatalog.search(self.search, group: nil, limit: 700)
      return stride(from: 0, to: values.count, by: 24).map { start in
        ("Search", Array(values[start..<min(start + 24, values.count)]))
      }
    }
    let recentEntries = self.recent.map {
      EmojiCatalogEntry(group: "Recent", name: $0, emoji: $0)
    }
    var entries = [(group: String, entries: [EmojiCatalogEntry])]()
    for start in stride(from: 0, to: recentEntries.count, by: 24) {
      entries.append(("Recent", Array(recentEntries[start..<min(start + 24,
                                                               recentEntries.count)])))
    }
    entries += EmojiCatalog.categorizedPages.map {
      (group: $0.group, entries: $0.emoji)
    }
    return entries
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
          self.emojiPager
        }
      }
      .frame(height: 3 * KeyboardChromeMetrics.keyHeight
        + 2 * KeyboardLayoutGeometry.alphabetRowSpacing.kbScaled)

      self.bottomRow
        .padding(.top, KeyboardLayoutGeometry.alphabetRowSpacing.kbScaled)
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    .onAppear { self.recent = EmojiCatalog.recent() }
    .onDisappear { self.tonePickerCells.removeAll() }
    .onChange(of: self.search) { _, _ in
      self.pageIndex = 0
    }
    .onChange(of: self.pageIndex) { _, index in
      guard let index, self.pages.indices.contains(index) else { return }
      self.selectedGroup = self.pages[index].group
    }
  }

  private var emojiPager: some View {
    GeometryReader { geometry in
      let pages = self.pages
      if pages.isEmpty {
        Text("No Emoji found")
          .font(.callout)
          .foregroundStyle(.secondary)
          .frame(maxWidth: .infinity, maxHeight: .infinity)
      } else {
        ScrollView(.horizontal) {
          LazyHStack(spacing: 0) {
            ForEach(pages.indices, id: \.self) { index in
              LazyVGrid(columns: self.columns,
                        spacing: KeyboardLayoutGeometry.alphabetRowSpacing.kbScaled) {
                ForEach(Array(pages[index].entries.enumerated()),
                        id: \.offset) { column, entry in
                  EmojiTouchCell(
                    entry: entry,
                    column: column % 8,
                    row: column / 8,
                    cellWidth: max(1, (geometry.size.width - 10.kbScaled) / 8),
                    pagerSize: geometry.size,
                    onChoosingChanged: { choosing in
                      let id = "\(index):\(column)"
                      if choosing { self.tonePickerCells.insert(id) }
                      else { self.tonePickerCells.remove(id) }
                    },
                    onChoose: { choice, tone in
                      KeyboardHaptics.key()
                      if let tone { EmojiCatalog.preferredTone = tone }
                      self.onInsertEmoji(choice)
                      FeatureDiagnostics.record(.keyboardEmoji, .selected)
                      // Persist for the next Emoji keyboard visit. Keep this
                      // visible page fixed so consecutive taps hit the same cell.
                      _ = EmojiCatalog.remember(choice)
                    }
                  )
                }
              }
              .padding(.horizontal, 5.kbScaled)
              .frame(width: geometry.size.width, height: geometry.size.height,
                     alignment: .top)
              .id(index)
            }
          }
          .scrollTargetLayout()
        }
        .scrollTargetBehavior(.paging)
        .scrollPosition(id: self.$pageIndex)
        .scrollIndicators(.hidden)
        .scrollDisabled(!self.tonePickerCells.isEmpty)
        .scrollClipDisabled()
      }
    }
  }

  private var searchToolbar: some View {
    HStack(spacing: 7.kbScaled) {
      if self.keyboardState.needsInputModeSwitchKey || self.keyboardState.showGlobeKey {
        NativeInputModeSwitchKey(
          configure: self.keyboardState.configureInputModeListButton,
          iconName: "globe"
        )
        .frame(width: 44.kbScaled, height: KeyboardChromeMetrics.keyHeight)
      }
      HStack(spacing: 6.kbScaled) {
        Image(systemName: "magnifyingglass")
          .foregroundStyle(.secondary)
        Button {
          self.searchActive = true
        } label: {
          Text(verbatim: self.search.isEmpty ? "Search Emoji" : self.search)
            .font(.system(size: 16.kbScaled))
            .foregroundStyle(self.search.isEmpty ? .secondary : .primary)
            .lineLimit(1)
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        if !self.search.isEmpty {
          Button {
            self.search = ""
          } label: {
            Image(systemName: "xmark.circle.fill")
              .font(.system(size: 16.kbScaled))
              .foregroundStyle(.secondary)
          }
          .buttonStyle(.plain)
          .accessibilityLabel("Clear search text")
        }
      }
      .padding(.horizontal, 12.kbScaled)
      .frame(height: KeyboardChromeMetrics.keyHeight)
      .background(Color(uiColor: KeyboardPalette.keyFill),
                  in: RoundedRectangle(cornerRadius: 12.kbScaled))

      Button {
        if self.search.isEmpty {
          self.onClose()
        } else {
          self.search = ""
          self.searchActive = false
        }
      } label: {
        Image(systemName: "xmark")
          .font(.system(size: 17.kbScaled, weight: .semibold))
          .frame(width: 44.kbScaled, height: KeyboardChromeMetrics.keyHeight)
          .background(Color(uiColor: KeyboardPalette.keyFill),
                      in: Capsule())
      }
      .buttonStyle(.plain)
      .accessibilityLabel(self.search.isEmpty ? "Close Emoji" : "Clear Emoji search")
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
      if self.searchActive {
        KeyButton(content: .text("Space")) {
          self.search += " "
        }
        .accessibilityLabel("Space in Emoji search")
      } else {
        ScrollView(.horizontal) {
          HStack(spacing: 4.kbScaled) {
            ForEach(Array(Self.categories.enumerated()), id: \.offset) { _, category in
              Button {
                self.selectedGroup = category.name
                self.search = ""
                self.searchActive = false
                self.pageIndex = self.pages.firstIndex { $0.group == category.name }
              } label: {
                Image(systemName: category.icon)
                  .font(.system(size: 19.kbScaled, weight: .regular))
                  .foregroundStyle(
                    self.selectedGroup == category.name ? Color.primary : Color.secondary
                  )
                  .frame(width: 44.kbScaled, height: KeyboardChromeMetrics.keyHeight)
                  .contentShape(Rectangle())
              }
              .buttonStyle(.plain)
              .accessibilityLabel(category.name)
            }
          }
        }
        .scrollIndicators(.hidden)
      }

      KeyButton(content: .systemImage("delete.left"), fixedWidth: 46.kbScaled) {
        if self.searchActive && !self.search.isEmpty {
          self.search.removeLast()
        } else if !self.searchActive {
          self.proxy.deleteBackward()
        }
      }
      .accessibilityLabel(self.searchActive ? "Delete search text" : "Delete backward")
      KeyButton(content: .systemImage("return.left"), fixedWidth: 48.kbScaled) {
        if self.searchActive {
          self.searchActive = false
        } else {
          self.proxy.insertText("\n")
        }
      }
      .accessibilityLabel(self.searchActive ? "Show Emoji results" : "Return")
    }
    .padding(.horizontal, KeyboardLayoutGeometry.alphabetSpecialRowInset.kbScaled)
    .padding(.bottom, 4.kbScaled)
  }
}

/// Tapping uses the saved skin tone; holding shows the native-style variant row.
/// Every cell uses the same immediate UIView touch primitive as alphabet keys.
private struct EmojiTouchCell: View {
  let entry: EmojiCatalogEntry
  let column: Int
  let row: Int
  let cellWidth: CGFloat
  let pagerSize: CGSize
  let onChoosingChanged: (Bool) -> Void
  let onChoose: (String, Int?) -> Void

  @Environment(\.layoutDirection) private var layoutDirection
  @State private var pressed = false
  @State private var choosing = false
  @State private var selection = 0
  @State private var latestTouch = CGPoint.zero
  @State private var holdTask: Task<Void, Never>?

  private var variants: [EmojiCatalogEntry] {
    EmojiCatalog.skinVariants(for: self.entry.emoji)
  }

  private var pickerGeometry: EmojiTonePickerGeometry {
    let physicalColumn = self.layoutDirection == .leftToRight ? self.column : 7 - self.column
    let cellX = 5.kbScaled + CGFloat(physicalColumn) * self.cellWidth
    let cellY = CGFloat(self.row) * (
      KeyboardChromeMetrics.keyHeight + KeyboardLayoutGeometry.alphabetRowSpacing.kbScaled
    )
    let toolbarHeight = KeyboardChromeMetrics.keyHeight
      + KeyboardLayoutGeometry.alphabetToolbarTopInset.kbScaled
      + KeyboardLayoutGeometry.alphabetToolbarBottomInset.kbScaled
    return EmojiTonePickerGeometry(
      cellWidth: Double(self.cellWidth), itemWidth: Double(36.kbScaled),
      itemHeight: Double((self.variants.count > 6 ? 36 : 43).kbScaled),
      padding: Double(6.kbScaled), itemCount: self.variants.count,
      alignRight: physicalColumn >= 4,
      bounds: .init(
        minX: Double(-cellX), maxX: Double(self.pagerSize.width - cellX),
        minY: Double(-toolbarHeight - cellY), maxY: Double(self.pagerSize.height - cellY)
      )
    )
  }

  var body: some View {
    Text(verbatim: EmojiCatalog.emoji(
      self.entry.emoji, withTone: EmojiCatalog.preferredTone
    ))
      .font(.system(size: 34.kbScaled))
      .frame(maxWidth: .infinity)
      .frame(height: KeyboardChromeMetrics.keyHeight)
      .background {
        if self.pressed {
          RoundedRectangle(cornerRadius: 8.kbScaled)
            .fill(Color(uiColor: KeyboardPalette.pressedFill).opacity(0.4))
        }
      }
      .contentShape(Rectangle())
      .overlay {
        ImmediateKeyTouchSurface(
          onBegan: { point in self.begin(at: point) },
          onMoved: { point, _ in self.move(to: point) },
          onEnded: { point in self.end(at: point) },
          onCancelled: { self.cancel() }
        )
        .accessibilityHidden(true)
      }
      .overlay(alignment: .top) {
        if self.choosing {
          self.skinPopup
            .offset(x: CGFloat(self.pickerGeometry.centerOffsetX),
                    y: CGFloat(self.pickerGeometry.originY))
            .allowsHitTesting(false)
        }
      }
      .zIndex(self.choosing ? 100 : 0)
      .accessibilityElement()
      .accessibilityAddTraits(.isButton)
      .accessibilityLabel(self.entry.name)
      .accessibilityHint(self.variants.isEmpty ? "" : "Additional actions choose a skin tone")
      .accessibilityAction {
        self.onChoose(EmojiCatalog.emoji(
          self.entry.emoji, withTone: EmojiCatalog.preferredTone
        ), nil)
      }
      .accessibilityActions {
        ForEach(self.variants) { variant in
          Button(variant.name) {
            self.cancel()
            self.onChoose(variant.emoji, EmojiCatalog.selectedTone(for: variant.emoji))
          }
        }
      }
      .onDisappear { self.cancel() }
  }

  private var skinPopup: some View {
    let geometry = self.pickerGeometry
    let variants = self.variants
    return VStack(alignment: .leading, spacing: 0) {
      ForEach(0..<geometry.rows, id: \.self) { row in
        HStack(spacing: 0) {
          ForEach(row * geometry.columns..<min((row + 1) * geometry.columns, variants.count),
                  id: \.self) { index in
            Text(verbatim: variants[index].emoji)
              .font(.system(size: 25.kbScaled))
              .frame(width: CGFloat(geometry.resolvedItemWidth),
                     height: CGFloat(geometry.resolvedItemHeight))
              .background {
                if index == self.selection {
                  RoundedRectangle(cornerRadius: 7.kbScaled)
                    .fill(Color(uiColor: KeyboardPalette.pressedFill))
                }
              }
          }
        }
        .frame(width: CGFloat(geometry.popupWidth - 2 * geometry.padding), alignment: .leading)
      }
    }
    .fixedSize(horizontal: true, vertical: true)
    .padding(CGFloat(geometry.padding))
    .environment(\.layoutDirection, .leftToRight)
    .background(
      Color(uiColor: KeyboardPalette.keyFill),
      in: RoundedRectangle(cornerRadius: 18.kbScaled)
    )
    .shadow(color: .black.opacity(0.25), radius: 4.kbScaled, y: 2.kbScaled)
  }

  private func begin(at point: CGPoint) {
    self.cancel()
    self.pressed = true
    self.latestTouch = point
    guard self.variants.count > 1 else { return }
    self.holdTask = Task { @MainActor in
      do { try await Task.sleep(for: .milliseconds(325)) } catch { return }
      guard !Task.isCancelled, self.pressed else { return }
      self.setChoosing(true)
      self.updateSelection()
      KeyboardHaptics.key()
    }
  }

  private func move(to point: CGPoint) {
    self.latestTouch = point
    if self.choosing { self.updateSelection() }
  }

  private func updateSelection() {
    if let index = self.pickerGeometry.selection(
      atX: Double(self.latestTouch.x), y: Double(self.latestTouch.y)
    ) {
      self.selection = index
    }
  }

  private func setChoosing(_ value: Bool) {
    guard self.choosing != value else { return }
    self.choosing = value
    self.onChoosingChanged(value)
  }

  private func end(at point: CGPoint) {
    guard self.pressed else { return }
    self.move(to: point)
    let item = self.choosing && !self.variants.isEmpty
      ? self.variants[self.selection].emoji
      : EmojiCatalog.emoji(self.entry.emoji, withTone: EmojiCatalog.preferredTone)
    let tone = self.choosing ? EmojiCatalog.selectedTone(for: item) : nil
    self.cancel()
    self.onChoose(item, tone)
  }

  private func cancel() {
    self.holdTask?.cancel()
    self.holdTask = nil
    self.pressed = false
    self.setChoosing(false)
  }
}
