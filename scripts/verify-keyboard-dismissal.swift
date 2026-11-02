import Foundation

@main
struct VerifyKeyboardDismissal {
  static func main() {
    precondition(KeyboardEdgeDismissalPolicy.acceptsTouch(atTopY: 0))
    precondition(KeyboardEdgeDismissalPolicy.acceptsTouch(atTopY: 20))
    precondition(!KeyboardEdgeDismissalPolicy.acceptsTouch(atTopY: 45))
    precondition(!KeyboardEdgeDismissalPolicy.acceptsTouch(atTopY: -1))
    precondition(KeyboardEdgeDismissalPolicy.shouldDismiss(
      translation: CGPoint(x: 0, y: 64), verticalVelocity: 200
    ))
    precondition(KeyboardEdgeDismissalPolicy.shouldDismiss(
      translation: CGPoint(x: 4, y: 32), verticalVelocity: 750
    ))
    precondition(!KeyboardEdgeDismissalPolicy.shouldDismiss(
      translation: CGPoint(x: 0, y: 18), verticalVelocity: 900
    ))
    precondition(!KeyboardEdgeDismissalPolicy.shouldDismiss(
      translation: CGPoint(x: 75, y: 60), verticalVelocity: 850
    ))
    precondition(!KeyboardEdgeDismissalPolicy.shouldDismiss(
      translation: CGPoint(x: 0, y: -90), verticalVelocity: -900
    ))
    precondition(KeyboardEdgeDismissalPolicy.visualProgress(
      translation: CGPoint(x: 0, y: 140)
    ) == 1)
    print("Top-edge keyboard dismissal policy verified")
  }
}
