import Foundation

@objcMembers
private final class SampleDocumentProxy: NSObject {
  dynamic var documentIdentifier: NSUUID?
}

@objcMembers
private final class WrongTypeDocumentProxy: NSObject {
  dynamic var documentIdentifier: NSString? = "invalid"
}

let sample = SampleDocumentProxy()
let first = UUID()
let second = UUID()

// A transient nil from UIKit must never crash the extension.
assert(KeyboardDocumentIdentifier.read(from: sample) == nil)
assert(KeyboardDocumentIdentifier.read(from: NSObject()) == nil)
assert(KeyboardDocumentIdentifier.read(from: WrongTypeDocumentProxy()) == nil)

sample.documentIdentifier = NSUUID(uuidString: first.uuidString)
assert(KeyboardDocumentIdentifier.read(from: sample) == first)
assert(KeyboardDocumentIdentifier.isSameOrUnavailable(current: first, previous: first))
assert(KeyboardDocumentIdentifier.isSameOrUnavailable(current: nil, previous: first))
assert(!KeyboardDocumentIdentifier.isSameOrUnavailable(current: second, previous: first))
assert(!KeyboardDocumentIdentifier.isSameOrUnavailable(current: first, previous: nil))

sample.documentIdentifier = nil
assert(KeyboardDocumentIdentifier.read(from: sample) == nil)
sample.documentIdentifier = NSUUID(uuidString: second.uuidString)
assert(KeyboardDocumentIdentifier.read(from: sample) == second)

print("Keyboard document identity: valid, absent, wrong type, and recovery PASS")
