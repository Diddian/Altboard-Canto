import Foundation
import ObjectiveC

/// Reads the host field identity without Swift's nonoptional UUID bridge.
///
/// UITextDocumentProxy.documentIdentifier is imported as UUID, although UIKit
/// may transiently return a null Objective-C value during field transitions.
/// This selector is a public UIKit property, not a private API. Never persist
/// or log the identifier itself.
enum KeyboardDocumentIdentifier {
  static func read(from proxy: NSObjectProtocol) -> UUID? {
    // Keep Selector local to avoid a shared non-Sendable global in Swift 6.
    let selector = NSSelectorFromString("documentIdentifier")
    guard proxy.responds(to: selector),
          let object = proxy.perform(selector)?.takeUnretainedValue(),
          let objcIdentifier = object as? NSUUID else {
      return nil
    }
    return UUID(uuidString: objcIdentifier.uuidString)
  }

  /// If UIKit has no current identity, avoid treating that absence as a new
  /// document. Callers that insert/delete text must still require a valid ID.
  static func isSameOrUnavailable(current: UUID?, previous: UUID?) -> Bool {
    current == nil || current == previous
  }
}
