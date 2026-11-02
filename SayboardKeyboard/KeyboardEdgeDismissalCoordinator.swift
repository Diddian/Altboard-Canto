import UIKit

/// Only top-edge touches activate the recognizer. UIKit moves and fades the
/// keyboard while dragging; the system owns the final dismissal animation.
@MainActor
final class KeyboardEdgeDismissalCoordinator: NSObject, UIGestureRecognizerDelegate {
  private weak var keyboardController: UIInputViewController?
  private weak var contentView: UIView?
  private var isDismissing = false

  init(keyboardController: UIInputViewController, contentView: UIView) {
    self.keyboardController = keyboardController
    self.contentView = contentView
    super.init()
    let pan = UIPanGestureRecognizer(target: self, action: #selector(handlePan(_:)))
    pan.maximumNumberOfTouches = 1
    pan.cancelsTouchesInView = false
    pan.delaysTouchesBegan = false
    pan.delegate = self
    contentView.addGestureRecognizer(pan)
  }

  func gestureRecognizer(
    _ gestureRecognizer: UIGestureRecognizer, shouldReceive touch: UITouch
  ) -> Bool {
    guard let contentView else { return false }
    return KeyboardEdgeDismissalPolicy.acceptsTouch(atTopY: touch.location(in: contentView).y)
  }

  func gestureRecognizer(
    _ gestureRecognizer: UIGestureRecognizer,
    shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer
  ) -> Bool {
    true
  }

  @objc private func handlePan(_ pan: UIPanGestureRecognizer) {
    guard !self.isDismissing, let contentView else { return }
    let translation = pan.translation(in: contentView)
    switch pan.state {
    case .began, .changed:
      let progress = KeyboardEdgeDismissalPolicy.visualProgress(translation: translation)
      contentView.transform = CGAffineTransform(translationX: 0, y: progress * 86)
      contentView.alpha = 1 - progress * 0.70
    case .ended:
      let dismiss = KeyboardEdgeDismissalPolicy.shouldDismiss(
        translation: translation, verticalVelocity: pan.velocity(in: contentView).y
      )
      if dismiss, let keyboardController {
        self.isDismissing = true
        KeyboardInputTrace.record(.keyboardDismissRequested)
        keyboardController.dismissKeyboard()
      } else {
        self.resetVisuals(animated: true)
      }
    case .cancelled, .failed:
      self.resetVisuals(animated: true)
    default:
      break
    }
  }

  func resetVisuals(animated: Bool) {
    guard let contentView else { return }
    let reset = {
      contentView.transform = CGAffineTransform.identity
      contentView.alpha = 1
    }
    self.isDismissing = false
    if animated {
      UIView.animate(
        withDuration: 0.18, delay: 0,
        options: [.beginFromCurrentState, .allowUserInteraction, .curveEaseOut],
        animations: reset
      )
    } else {
      contentView.layer.removeAllAnimations()
      reset()
    }
  }
}
