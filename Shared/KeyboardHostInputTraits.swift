import UIKit

/// UIKit input traits of the active host field. Never infer these from typed
/// content and never retain text from the host document.
struct KeyboardHostInputTraits: Equatable {
  var keyboardType: UIKeyboardType = .default
  var returnKeyType: UIReturnKeyType = .default
  var contentType: String?
  var autocapitalizationType: UITextAutocapitalizationType = .sentences
  var enablesReturnKeyAutomatically = false
  var hasText = false

  var bottomShortcuts: [String] {
    switch self.keyboardType {
    case .emailAddress: return ["@", "."]
    case .URL: return [".", "/", ".com"]
    case .webSearch: return ["."]
    case .twitter: return ["@", "#"]
    case .namePhonePad: return ["+", "#"]
    case .phonePad: return ["+", "*", "#"]
    case .decimalPad: return ["."]
    default:
      if self.contentType == UITextContentType.emailAddress.rawValue {
        return ["@", "."]
      }
      if self.contentType == UITextContentType.URL.rawValue {
        return [".", "/", ".com"]
      }
      return []
    }
  }

  var usesASCIITypingOnly: Bool {
    switch self.keyboardType {
    case .emailAddress, .URL, .asciiCapable:
      true
    default:
      self.contentType == UITextContentType.emailAddress.rawValue
        || self.contentType == UITextContentType.URL.rawValue
    }
  }

  var prefersLowercase: Bool {
    if self.autocapitalizationType == .none { return true }
    if self.keyboardType == .emailAddress || self.keyboardType == .URL {
      return true
    }
    return self.contentType == UITextContentType.emailAddress.rawValue
      || self.contentType == UITextContentType.URL.rawValue
  }

  var prefersNumberPage: Bool {
    switch self.keyboardType {
    case .numbersAndPunctuation, .numberPad, .decimalPad, .asciiCapableNumberPad,
         .phonePad:
      true
    default:
      false
    }
  }

  var returnEnabled: Bool {
    !self.enablesReturnKeyAutomatically || self.hasText
  }

  var returnAppearance: KeyboardReturnAppearance {
    switch self.returnKeyType {
    case .default:
      KeyboardReturnAppearance(icon: "return.left", title: "Return", prominent: false)
    case .go:
      KeyboardReturnAppearance(icon: "arrow.right", title: "Go", prominent: true)
    case .next:
      KeyboardReturnAppearance(icon: "arrow.right", title: "Next", prominent: true)
    case .done:
      KeyboardReturnAppearance(icon: "checkmark", title: "Done", prominent: true)
    case .search:
      KeyboardReturnAppearance(icon: "magnifyingglass", title: "Search", prominent: true)
    case .google:
      KeyboardReturnAppearance(icon: nil, title: "Google", prominent: true)
    case .yahoo:
      KeyboardReturnAppearance(icon: nil, title: "Yahoo", prominent: true)
    case .send:
      KeyboardReturnAppearance(icon: "arrow.up", title: "Send", prominent: true)
    case .join:
      KeyboardReturnAppearance(icon: nil, title: "Join", prominent: true)
    case .route:
      KeyboardReturnAppearance(icon: nil, title: "Route", prominent: true)
    case .emergencyCall:
      KeyboardReturnAppearance(icon: nil, title: "Emergency", prominent: true)
    case .continue:
      KeyboardReturnAppearance(icon: "arrow.right", title: "Continue", prominent: true)
    @unknown default:
      KeyboardReturnAppearance(icon: "return.left", title: "Return", prominent: false)
    }
  }
}

struct KeyboardReturnAppearance: Equatable {
  let icon: String?
  let title: String
  let prominent: Bool
}
