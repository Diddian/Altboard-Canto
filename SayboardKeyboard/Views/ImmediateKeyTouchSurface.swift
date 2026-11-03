import SwiftUI
import UIKit

struct ImmediateKeyTouchSurface: UIViewRepresentable {
  let onBegan: (CGPoint) -> Void
  let onMoved: (CGPoint, CGPoint) -> Void
  let onEnded: (CGPoint) -> Void
  let onCancelled: () -> Void

  func makeUIView(context: Context) -> ImmediateKeyTouchView {
    let view = ImmediateKeyTouchView()
    view.backgroundColor = .clear
    view.isOpaque = false
    view.isMultipleTouchEnabled = false
    view.isAccessibilityElement = false
    self.updateUIView(view, context: context)
    return view
  }

  func updateUIView(_ uiView: ImmediateKeyTouchView, context: Context) {
    uiView.onBegan = self.onBegan
    uiView.onMoved = self.onMoved
    uiView.onEnded = self.onEnded
    uiView.onCancelled = self.onCancelled
  }
}

final class ImmediateKeyTouchView: UIView {
  var onBegan: ((CGPoint) -> Void)?
  var onMoved: ((CGPoint, CGPoint) -> Void)?
  var onEnded: ((CGPoint) -> Void)?
  var onCancelled: (() -> Void)?

  private var activeTouch: UITouch?
  private var initialPoint: CGPoint = .zero

  override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
    guard self.activeTouch == nil, let touch = touches.first else { return }
    self.activeTouch = touch
    self.initialPoint = touch.location(in: self)
    self.onBegan?(self.initialPoint)
  }

  override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
    guard let active = self.activeTouch, touches.contains(active) else { return }
    self.onMoved?(active.location(in: self), self.initialPoint)
  }

  override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
    guard let active = self.activeTouch, touches.contains(active) else { return }
    let point = active.location(in: self)
    self.activeTouch = nil
    self.onEnded?(point)
  }

  override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) {
    guard let active = self.activeTouch, touches.contains(active) else { return }
    self.activeTouch = nil
    self.onCancelled?()
  }
}
