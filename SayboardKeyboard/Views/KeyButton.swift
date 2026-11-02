import SwiftUI
import UIKit

enum KeyContent {
  case text(LocalizedStringKey)
  case systemImage(String)
  case nativeEmojiGlyph
  case symbol(String, fontSize: CGFloat? = nil)
}

struct KeyButton: View {

  let content: KeyContent
  var fixedWidth: CGFloat?
  var shape = KeyShape.rounded
  var pressEffect = true
  var fillOnPress = false
  var showsCallout = false
  var calloutRowSpacing: CGFloat = 0
  var calloutAlignment = KeyCalloutAlignment.center
  var firesHaptic = true
  var systemIconSize: CGFloat = 18
  let action: () -> Void

  var body: some View {
    Button {
      self.action()
    } label: {
      self.contentView
    }
    .buttonStyle(RectKeyStyle(
      fixedWidth: self.fixedWidth,
      shape: self.shape,
      pressEffect: self.pressEffect,
      fillOnPress: self.fillOnPress,
      pressedBinding: self.$isPressed,
      visualOverride: self.recentlyPressed,
    ))
    .onChange(of: self.isPressed) { _, isDown in
      self.releaseHighlightTask?.cancel()
      if isDown {
        self.recentlyPressed = false
        if self.firesHaptic { KeyboardHaptics.key() }
      } else {
        // Quick taps can begin/end within one display frame.
        self.recentlyPressed = self.pressEffect
        self.releaseHighlightTask = Task { @MainActor in
          do { try await Task.sleep(for: .milliseconds(80)) } catch { return }
          guard !Task.isCancelled else { return }
          self.recentlyPressed = false
        }
      }
    }
    .onDisappear {
      self.releaseHighlightTask?.cancel()
      self.recentlyPressed = false
    }
    .overlay(alignment: .top) {
      if self.showsCallout {
        self.calloutOverlay
      }
    }
    .zIndex(self.showsCallout && self.isPressed ? 100 : 0)
  }

  @State private var isPressed = false
  @State private var recentlyPressed = false
  @State private var releaseHighlightTask: Task<Void, Never>?

  @ViewBuilder
  private var contentView: some View {
    switch self.content {
    case .text(let key):
      Text(key)
        .font(.system(size: 16.kbScaled))

    case .systemImage(let name):
      Image(systemName: name)
        .font(.system(size: self.systemIconSize.kbScaled))

    case .nativeEmojiGlyph:
      NativeEmojiGlyph()
        .fill(.primary, style: FillStyle(eoFill: true))
        .frame(width: 18.67.kbScaled, height: 18.67.kbScaled)

    case .symbol(let symbol, let fontSize):
      self.symbolText(symbol, fontSize: fontSize)
    }
  }

  private var calloutOverlay: some View {
    GeometryReader { geo in
      let topW = geo.size.width * KeyCalloutMetrics.topWidthMultiplier
      let neckH = self.calloutRowSpacing
      let totalH = geo.size.height + neckH + geo.size.height
      let posX = self.calloutPositionX(keyWidth: geo.size.width, topWidth: topW)
      KeyCallout(
        keyWidth: geo.size.width,
        keyHeight: geo.size.height,
        rowSpacing: self.calloutRowSpacing,
        alignment: self.calloutAlignment,
      ) { fontSize in
        self.calloutLabel(fontSize: fontSize)
      }
      .opacity(self.isPressed ? 1 : 0)
      .position(x: posX, y: geo.size.height - totalH / 2)
      .transaction(value: self.isPressed) { transaction in
        transaction.animation = self.isPressed ? nil : .easeOut(duration: 0.02).delay(0.01)
      }
    }
    .allowsHitTesting(false)
  }

  private func calloutPositionX(keyWidth: CGFloat, topWidth: CGFloat) -> CGFloat {
    switch self.calloutAlignment {
    case .center: keyWidth / 2
    case .left: topWidth / 2
    case .right: keyWidth - topWidth / 2
    }
  }

  private func calloutLabel(fontSize: CGFloat) -> some View {
    Group {
      switch self.content {
      case .text(let key):
        Text(key)
          .font(.system(size: fontSize))

      case .systemImage(let name):
        Image(systemName: name)
          .font(.system(size: fontSize))

      case .nativeEmojiGlyph:
        NativeEmojiGlyph()
          .fill(.primary, style: FillStyle(eoFill: true))
          .frame(width: fontSize, height: fontSize)

      case .symbol(let symbol, _):
        self.calloutSymbolText(symbol, fontSize: fontSize)
      }
    }
    .foregroundStyle(.primary)
  }

  /// Draw all symbols with font fallback. CoreText glyph paths can be empty
  /// for Traditional Chinese brackets and punctuation, leaving blank keys
  /// even though the underlying button continues to accept touches.
  private func symbolText(_ symbol: String, fontSize: CGFloat?) -> some View {
    Text(verbatim: symbol)
      .font(.system(size: (fontSize ?? 22).kbScaled, weight: .regular))
      .foregroundStyle(.primary)
      .lineLimit(1)
      .minimumScaleFactor(0.65)
  }

  private func calloutSymbolText(_ symbol: String, fontSize: CGFloat) -> some View {
    Text(verbatim: symbol)
      .font(.system(size: fontSize, weight: .regular))
      .foregroundStyle(.primary)
      .lineLimit(1)
  }
}
