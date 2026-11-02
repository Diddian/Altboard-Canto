import Foundation
import Testing

@Suite("Keyboard top-edge dismissal")
struct KeyboardEdgeDismissalPolicyTests {
  @Test func onlyTopEdgeActivates() {
    #expect(KeyboardEdgeDismissalPolicy.acceptsTouch(atTopY: 8))
    #expect(!KeyboardEdgeDismissalPolicy.acceptsTouch(atTopY: 55))
  }

  @Test func deliberateDownwardDragDismisses() {
    #expect(KeyboardEdgeDismissalPolicy.shouldDismiss(
      translation: CGPoint(x: 0, y: 75), verticalVelocity: 300
    ))
    #expect(KeyboardEdgeDismissalPolicy.shouldDismiss(
      translation: CGPoint(x: 4, y: 32), verticalVelocity: 700
    ))
  }

  @Test func horizontalShortAndUpwardGesturesStay() {
    #expect(!KeyboardEdgeDismissalPolicy.shouldDismiss(
      translation: CGPoint(x: 45, y: 12), verticalVelocity: 900
    ))
    #expect(!KeyboardEdgeDismissalPolicy.shouldDismiss(
      translation: CGPoint(x: 2, y: -80), verticalVelocity: -900
    ))
    #expect(!KeyboardEdgeDismissalPolicy.shouldDismiss(
      translation: CGPoint(x: 0, y: 22), verticalVelocity: 200
    ))
  }
}
