import SwiftUI
import UIKit

/// Five large stroke keys sharing UIKit's immediate touch-down handling.
struct ChineseStrokeGrid: View {
  let proxy: KeyboardProxy
  let onStroke: (String) -> Void
  let onPunctuation: (String) -> Void
  let onDelete: () -> Bool
  let onHostDeletion: () -> Void

  @State private var pressedIndex: Int?
  @State private var releasedIndex: Int?
  @State private var releaseTask: Task<Void, Never>?
  @State private var isChoosingSymbol = false
  @State private var highlightedOption = 0
  @State private var currentPoint = CGPoint.zero
  @State private var touchStartPoint = CGPoint.zero
  @State private var holdTask: Task<Void, Never>?

  var body: some View {
    GeometryReader { geometry in
      let inset = 6.kbScaled
      let gap = 8.kbScaled
      let fullWidth = max(0, geometry.size.width - 2 * inset)
      let keyWidth = max(30.kbScaled, (fullWidth - 2 * gap) / 3)
      let deleteWidth = 50.kbScaled
      let strokeHeight = max(45.kbScaled, (geometry.size.height - gap) / 2)
      // Preserve the original two-stroke width instead of stretching them
      // after removing the unused Shift key.
      let leadingSpace = max(0, fullWidth - 2 * keyWidth - deleteWidth - 3 * gap)
      let lowerX = inset + leadingSpace + gap

      ZStack(alignment: .topLeading) {
        VStack(spacing: gap) {
          HStack(spacing: gap) {
            ForEach(0..<3, id: \.self) { index in
              self.strokeKey(
                index, width: keyWidth, height: strokeHeight,
                origin: CGPoint(x: inset + CGFloat(index) * (keyWidth + gap), y: 0),
                availableSize: geometry.size
              )
            }
          }
          HStack(alignment: .bottom, spacing: gap) {
            Color.clear.frame(width: leadingSpace, height: 1)
            self.strokeKey(
              3, width: keyWidth, height: strokeHeight,
              origin: CGPoint(x: lowerX, y: strokeHeight + gap),
              availableSize: geometry.size
            )
            self.strokeKey(
              4, width: keyWidth, height: strokeHeight,
              origin: CGPoint(x: lowerX + keyWidth + gap, y: strokeHeight + gap),
              availableSize: geometry.size
            )
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
          self.symbolPopup(for: index, in: geometry.size)
            .zIndex(50)
            .allowsHitTesting(false)
            .accessibilityHidden(true)
        }
      }
      .frame(width: geometry.size.width, height: geometry.size.height,
             alignment: .topLeading)
    }
    .onDisappear {
      self.holdTask?.cancel()
      self.releaseTask?.cancel()
      self.pressedIndex = nil
      self.releasedIndex = nil
      self.isChoosingSymbol = false
    }
  }

  private func strokeKey(
    _ index: Int, width: CGFloat, height: CGFloat,
    origin: CGPoint, availableSize: CGSize
  ) -> some View {
    let key = ChineseStrokeKeys.keys[index]
    let active = self.pressedIndex == index || self.releasedIndex == index
    return ZStack(alignment: .topTrailing) {
      Text(verbatim: key.glyph)
        .font(.system(size: 49.kbScaled, weight: .regular))
        .foregroundStyle(.primary)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
      Text(verbatim: self.keyHint(for: index))
        .font(.system(size: 9.5.kbScaled, weight: .regular))
        .lineLimit(2)
        .multilineTextAlignment(.trailing)
        .foregroundStyle(.secondary)
        .padding(.top, 4.kbScaled)
        .padding(.trailing, 5.kbScaled)
        .allowsHitTesting(false)
    }
    .frame(width: width, height: height)
    .background(
      Color(uiColor: active ? KeyboardPalette.pressedFill : KeyboardPalette.keyFill),
      in: RoundedRectangle(cornerRadius: 9.kbScaled, style: .continuous)
    )
    .contentShape(Rectangle())
    .overlay {
      ImmediateKeyTouchSurface(
        onBegan: { point in
          self.beginTouch(index, at: point, origin: origin, size: availableSize)
        },
        onMoved: { point, _ in
          self.moveTouch(index, at: point, origin: origin, size: availableSize)
        },
        onEnded: { point in
          self.finishTouch(index, at: point, origin: origin, size: availableSize)
        },
        onCancelled: { self.cancelTouch() }
      )
      .accessibilityHidden(true)
    }
    .accessibilityElement()
    .accessibilityAddTraits(.isButton)
    .accessibilityLabel(key.accessibilityName)
    .accessibilityHint("長按滑動選擇數字或標點")
    .accessibilityAction { self.onStroke(key.code) }
  }

  private func keyHint(for index: Int) -> String {
    let options = ChineseStrokeKeys.alternates[index]
    if index < 3 {
      return options.prefix(4).joined(separator: " ") + "\n"
        + options.suffix(4).joined(separator: " ")
    }
    return options.joined(separator: " ")
  }

  private func gridPoint(_ local: CGPoint, origin: CGPoint) -> CGPoint {
    CGPoint(x: local.x + origin.x, y: local.y + origin.y)
  }

  private func beginTouch(
    _ index: Int, at point: CGPoint, origin: CGPoint, size: CGSize
  ) {
    self.cancelTouch()
    self.releaseTask?.cancel()
    self.releasedIndex = nil
    self.pressedIndex = index
    self.isChoosingSymbol = false
    self.currentPoint = self.gridPoint(point, origin: origin)
    self.touchStartPoint = self.currentPoint
    KeyboardHaptics.key()
    self.holdTask = Task { @MainActor in
      do { try await Task.sleep(for: .milliseconds(310)) } catch { return }
      guard !Task.isCancelled, self.pressedIndex == index else { return }
      self.isChoosingSymbol = true
      self.highlightedOption = self.optionIndex(
        at: self.currentPoint, for: index, in: size
      )
      KeyboardHaptics.key()
    }
  }

  private func moveTouch(
    _ index: Int, at point: CGPoint, origin: CGPoint, size: CGSize
  ) {
    guard self.pressedIndex == index else { return }
    self.currentPoint = self.gridPoint(point, origin: origin)
    if self.isChoosingSymbol {
      self.highlightedOption = self.optionIndex(
        at: self.currentPoint, for: index, in: size
      )
    }
  }

  private func finishTouch(
    _ index: Int, at point: CGPoint, origin: CGPoint, size: CGSize
  ) {
    guard self.pressedIndex == index else { return }
    let selected = self.isChoosingSymbol
      ? ChineseStrokeKeys.alternates[index][self.optionIndex(
          at: self.gridPoint(point, origin: origin), for: index, in: size
        )] : nil
    self.cancelTouch()
    self.releasedIndex = index
    self.releaseTask = Task { @MainActor in
      do { try await Task.sleep(for: .milliseconds(80)) } catch { return }
      guard !Task.isCancelled else { return }
      self.releasedIndex = nil
    }
    if let selected {
      self.onPunctuation(selected)
    } else {
      self.onStroke(ChineseStrokeKeys.keys[index].code)
    }
  }

  private func cancelTouch() {
    self.holdTask?.cancel()
    self.holdTask = nil
    self.pressedIndex = nil
    self.isChoosingSymbol = false
  }

  private func popupFrame(for index: Int, in size: CGSize) -> CGRect {
    let count = ChineseStrokeKeys.alternates[index].count
    let step = 36.kbScaled
    let padding = 8.kbScaled
    let width = min(size.width - 12.kbScaled, CGFloat(count) * step + 2 * padding)
    let height = 52.kbScaled
    let inset = 6.kbScaled
    let gap = 8.kbScaled
    let desired: CGFloat
    if index == 0 { desired = inset }
    else if index == 2 { desired = size.width - inset - width }
    else { desired = (size.width - width) / 2 }
    let x = min(max(inset, desired), size.width - inset - width)
    let strokeHeight = max(45.kbScaled, (size.height - gap) / 2)
    let y = index < 3 ? -height + 5.kbScaled : strokeHeight + gap - height + 5.kbScaled
    return CGRect(x: x, y: y, width: width, height: height)
  }

  private func optionIndex(
    at point: CGPoint, for index: Int, in size: CGSize
  ) -> Int {
    let frame = self.popupFrame(for: index, in: size)
    let count = ChineseStrokeKeys.alternates[index].count
    let itemWidth = (frame.width - 16.kbScaled) / CGFloat(count)
    return ChineseStrokeKeys.popupIndex(
      horizontalDelta: Double(point.x - self.touchStartPoint.x),
      optionCount: count,
      columnWidth: Double(itemWidth),
      startIndex: ChineseStrokeKeys.popupStartIndex(keyIndex: index, optionCount: count)
    )
  }

  private func symbolPopup(for index: Int, in size: CGSize) -> some View {
    let frame = self.popupFrame(for: index, in: size)
    let symbols = ChineseStrokeKeys.alternates[index]
    return HStack(spacing: 0) {
      ForEach(Array(symbols.enumerated()), id: \.offset) { option, symbol in
        Text(verbatim: symbol)
          .font(.system(size: 21.kbScaled, weight: .regular))
          .foregroundStyle(.primary)
          .frame(maxWidth: .infinity)
          .frame(height: 44.kbScaled)
          .background {
            if option == self.highlightedOption {
              RoundedRectangle(cornerRadius: 8.kbScaled)
                .fill(Color(uiColor: KeyboardPalette.pressedFill))
            }
          }
      }
    }
    .padding(.horizontal, 8.kbScaled)
    .padding(.vertical, 4.kbScaled)
    .frame(width: frame.width, height: frame.height)
    .background(
      Color(uiColor: KeyboardPalette.keyFill),
      in: RoundedRectangle(cornerRadius: 19.kbScaled, style: .continuous)
    )
    .overlay {
      RoundedRectangle(cornerRadius: 19.kbScaled)
        .stroke(Color.primary.opacity(0.10), lineWidth: 0.5.kbScaled)
    }
    .shadow(color: .black.opacity(0.24), radius: 5.kbScaled, y: 2.kbScaled)
    .position(x: frame.midX, y: frame.midY)
  }
}
