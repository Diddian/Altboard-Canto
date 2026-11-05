import Combine
import Foundation

@MainActor
final class KeyboardHostGeometry: ObservableObject {
  @Published private(set) var size = CGSize.zero

  func update(width: CGFloat, height: CGFloat) {
    guard width.isFinite, height.isFinite, width > 1, height > 1 else { return }
    let next = CGSize(width: width, height: height)
    if next != self.size { self.size = next }
  }
}
