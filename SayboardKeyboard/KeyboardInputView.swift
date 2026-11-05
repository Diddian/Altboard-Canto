import SwiftUI
import UIKit

/// The keyboard owns its height; the containing app owns its width.
final class KeyboardInputView: UIInputView {
  var contentHeight: CGFloat = KeyboardMetrics.baseHeight {
    didSet {
      guard self.contentHeight != oldValue else { return }
      self.invalidateIntrinsicContentSize()
      self.setNeedsLayout()
    }
  }

  override var intrinsicContentSize: CGSize {
    CGSize(width: UIView.noIntrinsicMetric, height: self.contentHeight)
  }

  override func systemLayoutSizeFitting(_ targetSize: CGSize) -> CGSize {
    CGSize(width: targetSize.width, height: self.contentHeight)
  }
}

/// Keep the hosting controller and render tree alive across focus changes.
/// Do not propose a zero or unbounded size to the keyboard's SwiftUI content.
struct KeyboardHostingRoot: View {
  let proxy: KeyboardProxy
  let keyboardState: KeyboardState
  @ObservedObject var geometry: KeyboardHostGeometry

  var body: some View {
    if self.geometry.size.width > 1, self.geometry.size.height > 1 {
      KeyboardView(proxy: self.proxy, keyboardState: self.keyboardState)
        .frame(width: self.geometry.size.width, height: self.geometry.size.height,
               alignment: .top)
        .onAppear {
          FeatureDiagnostics.record(.keyboardRender, .rootReady)
        }
    } else {
      Color.clear
        .onAppear {
          FeatureDiagnostics.record(.keyboardRender, .rootWaiting)
        }
    }
  }
}
