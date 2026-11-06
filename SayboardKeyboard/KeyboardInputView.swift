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
    // A host may briefly have zero bounds during an input-field transition.
    // Keep the keyboard mounted; the measured proposal updates on next layout.
    GeometryReader { bounds in
      let measured = bounds.size
      let width = measured.width > 1 ? measured.width : self.geometry.size.width
      let height = measured.height > 1 ? measured.height : self.geometry.size.height
      KeyboardView(proxy: self.proxy, keyboardState: self.keyboardState)
        .frame(width: max(1, width), height: max(1, height), alignment: .top)
        .onAppear {
          FeatureDiagnostics.record(
            .keyboardRender,
            measured.width > 1 && measured.height > 1 ? .rootReady : .rootWaiting
          )
        }
        .onChange(of: measured) { previous, next in
          if (previous.width <= 1 || previous.height <= 1)
            && next.width > 1 && next.height > 1 {
            FeatureDiagnostics.record(.keyboardRender, .rootReady)
          }
        }
    }
  }
}
