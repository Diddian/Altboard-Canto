import Combine
import CoreGraphics
import Foundation

@main
enum VerifyKeyboardHostGeometry {
  @MainActor
  static func main() {
    let geometry = KeyboardHostGeometry()
    var emissions = 0
    let subscription = geometry.$size.sink { _ in emissions += 1 }
    geometry.update(width: 0, height: 277)
    geometry.update(width: .nan, height: 277)
    precondition(geometry.size == .zero)
    precondition(emissions == 1)

    geometry.update(width: 440, height: 277)
    precondition(geometry.size == CGSize(width: 440, height: 277))
    precondition(emissions == 2)
    for _ in 0..<100 { geometry.update(width: 440, height: 277) }
    precondition(emissions == 2)

    // Temporary empty bounds during dismissal must not unmount the keyboard.
    geometry.update(width: 0, height: 0)
    geometry.update(width: -.infinity, height: 277)
    geometry.update(width: 440, height: .nan)
    precondition(geometry.size == CGSize(width: 440, height: 277))
    precondition(emissions == 2)

    geometry.update(width: 956, height: 277)
    geometry.update(width: 440, height: 150)
    precondition(geometry.size == CGSize(width: 440, height: 150))
    precondition(emissions == 4)
    withExtendedLifetime(subscription) {}
    print("Keyboard geometry ignores empty bounds and repeated layout passes")
  }
}
