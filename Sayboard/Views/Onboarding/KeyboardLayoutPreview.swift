
import SwiftUI
import UIKit

struct KeyboardLayoutPreview: View {

  static let backdrop = Color(uiColor: UIColor { traits in
    traits.userInterfaceStyle == .dark
      ? KeyboardPalette.darkBackdrop
      : UIColor(red: 0.875, green: 0.878, blue: 0.902, alpha: 1)
  })

  static let keyFill = Color(uiColor: KeyboardPalette.keyFill)

  let kind: KeyboardKind
  @AppStorage(
    SharedKey.keyboardLetterArrangement,
    store: UserDefaults(suiteName: AppGroup.identifier)
  )
  private var letterArrangementRaw = LetterKeyArrangement.qwertz.rawValue

  private var letters: [[String]] {
    (LetterKeyArrangement(rawValue: self.letterArrangementRaw) ?? .qwertz).rows
  }

  var body: some View {
    VStack(spacing: 0) {
      switch self.kind {
      case .standard: self.standardLayout
      case .extended: self.extendedLayout
      case .alphabetic: self.alphabeticLayout
      }
    }
    .padding(.top, self.kind == .alphabetic
      ? KeyboardLayoutGeometry.alphabetToolbarTopInset : Self.topPadding)
    .frame(width: Self.width, height: Self.size(for: self.kind).height, alignment: .top)
    .background(Self.backdrop)
    .accessibilityHidden(true)
  }

  static func size(for kind: KeyboardKind) -> CGSize {
    CGSize(width: Self.width, height: kind == .standard ? Self.standardHeight : Self.extendedHeight)
  }

  private static let width: CGFloat = 390
  private static let standardHeight: CGFloat = KeyboardLayoutGeometry.microphoneDefaultHeight
  private static let extendedHeight: CGFloat = KeyboardLayoutGeometry.fullTypingHeight
  private static let topPadding: CGFloat = 14.5
  private static let rowSpacing: CGFloat = 11
  private static let keyHeight: CGFloat = 45
  private static let keyRadius: CGFloat = 8
  private static let keySpacing: CGFloat = 6
  private static let sideKeyWidth: CGFloat = 45
  private static let returnKeyWidth: CGFloat = 96
  private static let edgeInset: CGFloat = 4
  private static let symbolSize: CGFloat = 18
  private static let characterSize: CGFloat = 22
  private static let micRowHeight: CGFloat = 168
  private static let micDiameter: CGFloat = 106
  private static let micTop: CGFloat = 28
  private static let micGlyph = CGSize(width: 56, height: 42)
  private static let chromeRowHeight: CGFloat = 57
  private static let chromeInset: CGFloat = 12
  private static let compactMicGlyph = CGSize(width: 32.06, height: 24.04)
  private static let punctuationKeyWidth: CGFloat = 44.87
  private static let wideKeyWidth: CGFloat = 54.84
  private static let groupGap: CGFloat = 12
  private static let numbersRow = ["1", "2", "3", "4", "5", "6", "7", "8", "9", "0"]
  private static let symbolsRow = ["-", "/", ":", ";", "(", ")", "$", "&", "@", "\""]
  private static let punctuationRow = [".", ",", "?", "!", "'"]

  private var standardLayout: some View {
    VStack(spacing: Self.rowSpacing) {
      ZStack(alignment: .top) {
        HStack(alignment: .bottom) {
          self.symbolKey("gearshape", width: Self.sideKeyWidth)
          Spacer(minLength: 0)
          self.symbolKey("delete.left", width: Self.sideKeyWidth)
        }
        .frame(maxHeight: .infinity, alignment: .bottom)
        MicMorphShape(frameIndex: 0)
          .fill(.primary)
          .frame(width: Self.micGlyph.width, height: Self.micGlyph.height)
          .frame(width: Self.micDiameter, height: Self.micDiameter)
          .background(Self.keyFill, in: Circle())
          .padding(.top, Self.micTop)
      }
      .padding(.horizontal, Self.edgeInset)
      .frame(height: Self.micRowHeight)
      self.bottomRow
    }
  }

  private var extendedLayout: some View {
    VStack(spacing: Self.rowSpacing) {
      HStack {
        self.symbolKey("gearshape", width: Self.sideKeyWidth, shape: .pill)
        Spacer(minLength: 0)
        MicMorphShape(frameIndex: 0)
          .fill(.primary)
          .frame(width: Self.compactMicGlyph.width, height: Self.compactMicGlyph.height)
          .frame(width: Self.returnKeyWidth, height: Self.keyHeight)
          .background(Self.keyFill, in: Capsule())
      }
      .padding(.horizontal, Self.chromeInset)
      .frame(height: Self.chromeRowHeight)
      self.characterRow(Self.numbersRow)
      self.characterRow(Self.symbolsRow)
      HStack(spacing: 0) {
        self.textKey("#+=", width: Self.wideKeyWidth, size: Self.symbolSize)
        HStack(spacing: Self.keySpacing) {
          ForEach(Self.punctuationRow, id: \.self) { self.textKey($0, width: Self.punctuationKeyWidth) }
        }
        .padding(.horizontal, Self.groupGap)
        self.symbolKey("delete.left", width: Self.wideKeyWidth)
      }
      .padding(.horizontal, Self.edgeInset)
      self.bottomRow
    }
  }

  private var alphabeticLayout: some View {
    VStack(spacing: Self.rowSpacing) {
      HStack(spacing: Self.keySpacing) {
        self.symbolKey("gearshape", width: Self.sideKeyWidth)
        Spacer()
        self.symbolKey("mic.fill", width: 86)
      }
      .padding(.horizontal, Self.edgeInset)
      .frame(height: Self.keyHeight)
      self.characterRow(self.letters[0], inset: 6.67)
      self.characterRow(self.letters[1], inset: 28)
      HStack(spacing: Self.keySpacing) {
        self.symbolKey("shift", width: 48)
        ForEach(self.letters[2], id: \.self) { key in
          self.textKey(key, width: nil)
        }
        self.symbolKey("delete.left", width: 48)
      }
      .padding(.horizontal, KeyboardLayoutGeometry.alphabetSpecialRowInset)
      HStack(spacing: Self.keySpacing) {
        self.textKey("?123", width: 48, size: 16)
        self.nativeGlobeKey(width: 48)
        ZStack(alignment: .bottomTrailing) {
          Color.clear
          Text("A")
            .font(.system(size: 10, weight: .medium))
            .foregroundStyle(.secondary)
            .padding(.trailing, 6)
            .padding(.bottom, 4)
        }
          .frame(maxWidth: .infinity)
          .frame(height: Self.keyHeight)
          .background(Self.keyFill,
            in: RoundedRectangle(cornerRadius: Self.keyRadius, style: .continuous))
        self.symbolKey("return.left", width: 102)
      }
      .padding(.horizontal, 6.67)
    }
  }

  private var bottomRow: some View {
    HStack(spacing: Self.keySpacing) {
      self.symbolKey("globe", width: Self.sideKeyWidth)
      self.symbolKey("trash", width: Self.sideKeyWidth)
      Color.clear
        .frame(maxWidth: .infinity)
        .frame(height: Self.keyHeight)
        .background(Self.keyFill, in: RoundedRectangle(cornerRadius: Self.keyRadius, style: .continuous))
      self.symbolKey("return.left", width: Self.returnKeyWidth)
    }
    .padding(.horizontal, Self.edgeInset)
  }

  private func characterRow(_ characters: [String], inset: CGFloat? = nil) -> some View {
    HStack(spacing: Self.keySpacing) {
      ForEach(characters, id: \.self) { self.textKey($0, width: nil) }
    }
    .padding(.horizontal, inset ?? Self.edgeInset)
  }

  private func nativeGlobeKey(width: CGFloat) -> some View {
    Image(systemName: "globe")
      .font(.system(size: 19, weight: .regular))
      .foregroundStyle(.primary)
      .frame(width: width, height: Self.keyHeight)
      .background(Self.keyFill,
        in: RoundedRectangle(cornerRadius: Self.keyRadius, style: .continuous))
  }

  private func textKey(_ text: String, width: CGFloat?, size: CGFloat = Self.characterSize) -> some View {
    Text(verbatim: text)
      .font(.system(size: size))
      .frame(maxWidth: width ?? .infinity)
      .frame(width: width, height: Self.keyHeight)
      .background(Self.keyFill, in: RoundedRectangle(cornerRadius: Self.keyRadius, style: .continuous))
  }

  @ViewBuilder
  private func symbolKey(
    _ name: String, width: CGFloat, shape: KeyPreviewShape = .rounded,
    size: CGFloat = Self.symbolSize
  ) -> some View {
    let glyph = Image(systemName: name)
      .font(.system(size: size))
      .frame(width: width, height: Self.keyHeight)
    switch shape {
    case .rounded:
      glyph.background(Self.keyFill, in: RoundedRectangle(cornerRadius: Self.keyRadius, style: .continuous))
    case .pill:
      glyph.background(Self.keyFill, in: Capsule())
    }
  }
}

private enum KeyPreviewShape {
  case rounded
  case pill
}
