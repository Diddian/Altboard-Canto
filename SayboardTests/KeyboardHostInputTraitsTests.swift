import Testing
import UIKit

@Suite("Host input field keyboard traits")
struct KeyboardHostInputTraitsTests {
  @Test func emailAndURLAddNativeShortcuts() {
    #expect(KeyboardHostInputTraits(keyboardType: .emailAddress).bottomShortcuts == ["@", "."])
    #expect(KeyboardHostInputTraits(keyboardType: .URL).bottomShortcuts == [".", "/", ".com"])
    #expect(SymbolKeyAlternates.choices(for: ".com").contains(".de"))
    #expect(KeyboardHostInputTraits(
      contentType: UITextContentType.emailAddress.rawValue
    ).bottomShortcuts == ["@", "."])
    #expect(KeyboardHostInputTraits(
      contentType: UITextContentType.URL.rawValue
    ).bottomShortcuts == [".", "/", ".com"])
  }

  @Test func searchAndSocialShortcuts() {
    #expect(KeyboardHostInputTraits(keyboardType: .webSearch).bottomShortcuts == ["."])
    #expect(KeyboardHostInputTraits(keyboardType: .twitter).bottomShortcuts == ["@", "#"])
    #expect(KeyboardHostInputTraits().bottomShortcuts.isEmpty)
    #expect(KeyboardHostInputTraits(keyboardType: .decimalPad).bottomShortcuts == ["."])
  }

  @Test func numericFieldsPreferNumbers() {
    #expect(KeyboardHostInputTraits(keyboardType: .numberPad).prefersNumberPage)
    #expect(KeyboardHostInputTraits(keyboardType: .decimalPad).prefersNumberPage)
    #expect(KeyboardHostInputTraits(keyboardType: .asciiCapableNumberPad).prefersNumberPage)
    #expect(!KeyboardHostInputTraits(keyboardType: .emailAddress).prefersNumberPage)
  }

  @Test func returnKeyFollowsHostIntent() {
    let search = KeyboardHostInputTraits(returnKeyType: .search)
    #expect(search.returnAppearance.title == "Search")
    #expect(search.returnAppearance.prominent)
    let next = KeyboardHostInputTraits(returnKeyType: .next)
    #expect(next.returnAppearance.icon == "arrow.right")
    #expect(next.returnAppearance.prominent)
    let plain = KeyboardHostInputTraits()
    #expect(plain.returnAppearance.title == "Return")
    #expect(!plain.returnAppearance.prominent)
  }

  @Test func returnEnablesOnTextOnlyWhenRequested() {
    #expect(!KeyboardHostInputTraits(
      enablesReturnKeyAutomatically: true
    ).returnEnabled)
    #expect(KeyboardHostInputTraits(
      enablesReturnKeyAutomatically: true, hasText: true
    ).returnEnabled)
    #expect(KeyboardHostInputTraits().returnEnabled)
  }

  @Test func hostAutocorrectionRestrictions() {
    #expect(KeyboardHostInputTraits(autocorrectionType: .no).disallowsAutoCorrection)
    #expect(KeyboardHostInputTraits(keyboardType: .emailAddress).disallowsAutoCorrection)
    #expect(KeyboardHostInputTraits(keyboardType: .URL).disallowsAutoCorrection)
    #expect(KeyboardHostInputTraits(keyboardType: .numberPad).disallowsAutoCorrection)
    #expect(!KeyboardHostInputTraits().disallowsAutoCorrection)
  }

  @Test func hostCapitalizationWinsInAddressFields() {
    #expect(KeyboardHostInputTraits(keyboardType: .URL).prefersLowercase)
    #expect(KeyboardHostInputTraits(
      autocapitalizationType: .none
    ).prefersLowercase)
    #expect(!KeyboardHostInputTraits().prefersLowercase)
  }
}
