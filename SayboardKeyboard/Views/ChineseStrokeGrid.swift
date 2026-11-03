import SwiftUI

/// Five-stroke input occupies exactly the existing alphabet key region.
/// Every stroke key accepts the same press-hold-slide-release gesture.
struct ChineseStrokeGrid: View {
  let proxy: KeyboardProxy
  let onStroke: (String) -> Void
  let onPunctuation: (String) -> Void
  let onDelete: () -> Bool
  let onHostDeletion: () -> Void

  @State private var pressedIndex: Int?
  @State private var isChoosingSymbol = false
  @State private var highlightedSymbol: String?
  @State private var touchPoint = CGPoint.zero
  @State private var holdTask: Task<Void, Never>?

  private let horizontalInset: CGFloat = 6
  private let gap: CGFloat = 8

  var body: some View {
    GeometryReader { geometry in
      let inset = self.horizontalInset.kbScaled
      let gap = self.gap.kbScaled
      let fullWidth = max(0, geometry.size.width - 2 * inset)
      let upperWidth = max(30.kbScaled, (fullWidth - 2 * gap) / 3)
      let deleteWidth = 50.kbScaled
      let lowerWidth = max(30.kbScaled, (fullWidth - deleteWidth - 2 * gap) / 2)
      let strokeHeight = max(45.kbScaled, (
        geometry.size.height - gap
      ) / 2)

      ZStack(alignment: .topLeading) {
        VStack(spacing: gap) {
          HStack(spacing: gap) {
            ForEach(0..<3, id: \.self) { index in
              self.strokeKey(index, size: geometry.size)
                .frame(width: upperWidth, height: strokeHeight)
            }
          }
          HStack(alignment: .bottom, spacing: gap) {
            ForEach(3..<5, id: \.self) { index in
              self.strokeKey(index, size: geometry.size)
                .frame(width: lowerWidth, height: strokeHeight)
            }
            RepeatDeleteButton(
              proxy: self.proxy,
              fixedWidth: deleteWidth,
              onDeleteIntercept: self.onDelete,
              onTapDeleteIntercept: self.onDelete,
              onHostDeletion: self.onHostDeletion,
              fastCompositionRepeat: true
            )
            .frame(width: deleteWidth, height: KeyboardChromeMetrics.keyHeight,
                   alignment: .bottom)
          }
        }
        .padding(.horizontal, inset)

        if let index = self.pressedIndex, self.isChoosingSymbol {
          self.symbolStrip(for: index, in: geometry.size)
            .allowsHitTesting(false)
            .zIndex(40)
        }
      }
      .frame(width: geometry.size.width, height: geometry.size.height,
             alignment: .topLeading)
      .coordinateSpace(name: "strokeGrid")
    }
    .onDisappear {
      self.holdTask?.cancel()
      self.pressedIndex = nil
      self.isChoosingSymbol = false
    }
  }

  private func strokeKey(_ index: Int, size: CGSize) -> some View {
    let key = ChineseStrokeKeys.keys[index]
    return Text(verbatim: key.glyph)
      .font(.system(size: 49.kbScaled, weight: .regular))
      .foregroundStyle(.primary)
      .frame(maxWidth: .infinity, maxHeight: .infinity)
      .background(
        Color(uiColor: KeyboardPalette.keyFill),
        in: RoundedRectangle(cornerRadius: 9.kbScaled, style: .continuous)
      )
      .contentShape(Rectangle())
      .gesture(
        DragGesture(minimumDistance: 0, coordinateSpace: .named("strokeGrid"))
          .onChanged { value in
            self.trackTouch(on: index, at: value.location, size: size)
          }
          .onEnded { value in
            self.finishTouch(on: index, at: value.location, size: size)
          }
      )
      .accessibilityElement()
      .accessibilityAddTraits(.isButton)
      .accessibilityLabel(key.accessibilityName)
      .accessibilityHint("長按後滑到數字或標點，放手輸入")
      .accessibilityAction {
        KeyboardHaptics.key()
        self.onStroke(key.code)
      }
      .accessibilityAction(named: "Symbols") {
        self.pressedIndex = index
        self.isChoosingSymbol = true
      }
  }

  private func trackTouch(on index: Int, at point: CGPoint, size: CGSize) {
    self.touchPoint = point
    if self.pressedIndex != index {
      self.holdTask?.cancel()
      self.pressedIndex = index
      self.isChoosingSymbol = false
      self.highlightedSymbol = nil
      self.holdTask = Task { @MainActor in
        do { try await Task.sleep(for: .milliseconds(310)) } catch { return }
        guard !Task.isCancelled, self.pressedIndex == index else { return }
        self.isChoosingSymbol = true
        self.highlightedSymbol = self.symbol(at: self.touchPoint,
                                             for: index, in: size)
        KeyboardHaptics.key()
      }
    } else if self.isChoosingSymbol {
      self.highlightedSymbol = self.symbol(at: point, for: index, in: size)
    }
  }

  private func finishTouch(on index: Int, at point: CGPoint, size: CGSize) {
    self.holdTask?.cancel()
    guard self.pressedIndex == index else { return }
    let held = self.isChoosingSymbol
    let selected = held ? self.symbol(at: point, for: index, in: size) : nil
    self.pressedIndex = nil
    self.isChoosingSymbol = false
    self.highlightedSymbol = nil

    if held {
      if let selected {
        KeyboardHaptics.key()
        self.onPunctuation(selected)
      }
    } else {
      KeyboardHaptics.key()
      self.onStroke(ChineseStrokeKeys.keys[index].code)
    }
  }

  private func stripFrame(for index: Int, in size: CGSize) -> CGRect {
    let upper = index < 3
    let columns = upper ? 4 : ChineseStrokeKeys.alternates[index].count
    let cellWidth = 37.kbScaled
    let cellHeight = KeyboardChromeMetrics.keyHeight
    let gap = 4.kbScaled
    let width = min(size.width - 12.kbScaled, CGFloat(columns) * cellWidth
      + CGFloat(columns - 1) * gap)
    let height = upper ? 2 * cellHeight + gap : cellHeight
    let x: CGFloat
    switch index {
    case 0, 3: x = 6.kbScaled
    case 1: x = (size.width - width) / 2
    case 2: x = size.width - 6.kbScaled - width
    default: x = max(6.kbScaled, size.width - 6.kbScaled
      - width - 50.kbScaled - self.gap.kbScaled)
    }
    let y = upper ? 0 : max(0, size.height - height)
    return CGRect(x: x, y: y, width: width, height: height)
  }

  private func symbol(at point: CGPoint, for index: Int, in size: CGSize) -> String? {
    let frame = self.stripFrame(for: index, in: size)
    guard frame.contains(point) else { return nil }
    let values = ChineseStrokeKeys.alternates[index]
    let columns = index < 3 ? 4 : values.count
    let cellGap = 4.kbScaled
    let cellWidth = (frame.width - CGFloat(columns - 1) * cellGap)
      / CGFloat(columns)
    let stepX = cellWidth + cellGap
    let stepY = KeyboardChromeMetrics.keyHeight + cellGap
    let localX = point.x - frame.minX
    let localY = point.y - frame.minY
    let column = min(columns - 1, Int(localX / stepX))
    let row = index < 3 ? min(1, Int(localY / stepY)) : 0
    let indexInRow = row * columns + column
    return values.indices.contains(indexInRow) ? values[indexInRow] : nil
  }

  private func symbolStrip(for index: Int, in size: CGSize) -> some View {
    let frame = self.stripFrame(for: index, in: size)
    let values = ChineseStrokeKeys.alternates[index]
    let columns = index < 3 ? 4 : values.count
    return LazyVGrid(
      columns: Array(repeating: GridItem(.flexible(), spacing: 4.kbScaled),
                     count: columns),
      spacing: 4.kbScaled
    ) {
      ForEach(Array(values.enumerated()), id: \.offset) { _, symbol in
        Text(verbatim: symbol)
          .font(.system(size: 19.kbScaled))
          .foregroundStyle(.primary)
          .frame(maxWidth: .infinity)
          .frame(height: KeyboardChromeMetrics.keyHeight)
          .background(
            Color(uiColor: symbol == self.highlightedSymbol
              ? KeyboardPalette.pressedFill : KeyboardPalette.keyFill),
            in: RoundedRectangle(cornerRadius: 7.kbScaled)
          )
      }
    }
    .padding(2.kbScaled)
    .frame(width: frame.width, height: frame.height)
    .background(
      Color(uiColor: KeyboardPalette.backdrop),
      in: RoundedRectangle(cornerRadius: 9.kbScaled)
    )
    .position(x: frame.midX, y: frame.midY)
  }
}
