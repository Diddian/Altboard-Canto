import SwiftUI

/// Visual-only key. Input is routed by the entire AlphabeticTouchRow, which
/// avoids individual SwiftUI button hitboxes and fills the spaces between keys.
struct AlphabeticLetterKey: View {
  let letter: String
  let uppercase: Bool
  let column: Int
  let rowCount: Int
  let secondarySymbol: String
  let pressed: Bool
  let choosing: Bool
  let selected: Int

  private var options: [String] {
    LetterKeyAlternates.holdChoices(for: self.letter, uppercase: self.uppercase,
                                    secondary: self.secondarySymbol)
  }

  private var expandsLeft: Bool {
    LetterHoldNavigation.expandsLeft(column: self.column, keyCount: self.rowCount)
  }

  private var popupAlignment: Alignment {
    self.expandsLeft ? .topTrailing : .topLeading
  }

  var body: some View {
    ZStack(alignment: .topTrailing) {
      Text(verbatim: self.uppercase ? self.letter.uppercased() : self.letter.lowercased())
        .font(.system(size: 21.kbScaled, weight: .regular, design: .default))
        .foregroundStyle(.primary)
        .offset(y: -1.2.kbScaled)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
      Text(verbatim: self.secondarySymbol)
        .font(.system(size: 8.5.kbScaled, weight: .regular))
        .fontWidth(.condensed)
        .foregroundStyle(Color.secondary.opacity(0.72))
        .padding(.top, 3.2.kbScaled)
        .padding(.trailing, 6.kbScaled)
    }
      .frame(maxWidth: .infinity)
      .frame(height: KeyboardChromeMetrics.keyHeight)
      .background {
        RoundedRectangle(cornerRadius: 8.kbScaled, style: .continuous)
          .fill(Color(self.pressed ? .keyPressedBackground : .keyBackground))
          .shadow(color: .black.opacity(0.13), radius: 0.5, y: 0.5)
      }
      .padding(.horizontal, 3.kbScaled)
      .overlay(alignment: self.popupAlignment) {
        if self.choosing {
          HStack(spacing: 0) {
            ForEach(LetterHoldNavigation.visualOrder(
              count: self.options.count, expandsLeft: self.expandsLeft
            ), id: \.self) { index in
              Text(verbatim: self.options[index])
                .font(.system(size: 22.kbScaled))
                .foregroundStyle(index == self.selected ? Color.white : Color.primary)
                .frame(width: 33.kbScaled, height: 43.kbScaled)
                .background {
                  if index == self.selected {
                    RoundedRectangle(cornerRadius: 5.kbScaled).fill(Color.accentColor)
                  }
                }
            }
          }
          .padding(3.kbScaled)
          .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 9.kbScaled))
          .shadow(color: .black.opacity(0.23), radius: 3, y: 2)
          .fixedSize(horizontal: true, vertical: true)
          .offset(y: -49.kbScaled)
          .allowsHitTesting(false)
          .transition(.identity)
        }
      }
      .zIndex(self.choosing ? 100 : 0)
      .accessibilityLabel(self.uppercase ? self.letter.uppercased() : self.letter.lowercased())
      .accessibilityHint(self.options.count > 1 ? "Hold for symbols or accented letters" : "")
  }
}
