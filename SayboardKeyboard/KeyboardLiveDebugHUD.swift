import UIKit

#if !APPSTORE
/// Event categories only: no host text, keystroke values or touch coordinates.
enum KeyboardLiveDebugAction: String {
  case letterTap = "key.letter"
  case symbolTap = "key.symbol"
  case textCommitted = "text.commit"
  case spaceCommitted = "key.space"
  case deleteBackward = "key.delete"
  case deleteWord = "key.deleteWord"
  case deleteAll = "key.deleteAll"
  case nextKeyboardRequested = "keyboard.next"
  case globeTouched = "keyboard.globeTouch"
  case micStart = "mic.start"
  case micStop = "mic.stop"
  case micCancel = "mic.cancel"
  case aiRequest = "ai.request"
  case cursorMove = "cursor.move"
  case swipeMoving = "swipe.move"
  case swipeCommitted = "swipe.commit"
  case pageChanged = "page.changed"
  case emojiOpened = "emoji.open"
  case emojiClosed = "emoji.close"
  case fieldTypeChanged = "field.type"
  case inputMethodChanged = "ime.changed"
}

/// UIKit-owned overlay remains independent of SwiftUI letter-row rendering.
@MainActor
final class KeyboardLiveDebugHUD: UIView {
  private let ink = UIColor(red: 0.22, green: 1.0, blue: 0.08, alpha: 1.0)
  private let label = UILabel()
  private let startedAt = CFAbsoluteTimeGetCurrent()
  private var lastPaintAt: CFAbsoluteTime = 0
  private var paintPending = false
  private var events = [String]()
  private var stateLine = "loading"
  private var geometryLine = "AB LIVE | measuring..."
  private var eventCount = 0
  private var swipeMoveCount = 0

  override init(frame: CGRect) {
    super.init(frame: frame)
    self.isUserInteractionEnabled = false
    self.isAccessibilityElement = false
    self.accessibilityElementsHidden = true
    self.backgroundColor = UIColor.black.withAlphaComponent(0.86)
    self.layer.cornerRadius = 5
    self.layer.borderWidth = 1.1
    self.layer.borderColor = self.ink.cgColor
    self.clipsToBounds = true
    self.label.font = .monospacedSystemFont(ofSize: 9, weight: .medium)
    self.label.textColor = self.ink
    self.label.numberOfLines = 4
    self.label.adjustsFontSizeToFitWidth = true
    self.label.minimumScaleFactor = 0.75
    self.label.translatesAutoresizingMaskIntoConstraints = false
    self.addSubview(self.label)
    NSLayoutConstraint.activate([
      self.label.leadingAnchor.constraint(equalTo: self.leadingAnchor, constant: 5),
      self.label.trailingAnchor.constraint(equalTo: self.trailingAnchor, constant: -5),
      self.label.topAnchor.constraint(equalTo: self.topAnchor, constant: 2),
      self.label.bottomAnchor.constraint(equalTo: self.bottomAnchor, constant: -2),
    ])
    self.appendEvent("hud.attached")
  }

  required init?(coder: NSCoder) { return nil }

  func recordLifecycle(
    event: String, requestedMode: String, effectiveMode: String,
    fallbackReason: String?, actualHeight: CGFloat, targetHeight: CGFloat,
    keyboardType: Int, probe: KeyboardLifecycleTrace.RenderProbe?
  ) {
    let reason: String
    switch fallbackReason {
    case "fullAccessUnavailable": reason = "access"
    case "appGroupUnavailable": reason = "group"
    case "microphoneUnavailable": reason = "mic"
    case "speechModelUnavailable": reason = "model"
    default: reason = "none"
    }
    self.stateLine = "\(requestedMode)>\(effectiveMode) fb:\(reason) type:\(keyboardType)"
    let actual = actualHeight.isFinite ? Int(actualHeight.rounded()) : -1
    let target = targetHeight.isFinite ? Int(targetHeight.rounded()) : -1
    let rows = probe.map {
      $0.letterRowsExpected ? "\($0.touchSurfacesInWindow)/3" : "n/a"
    } ?? "--"
    self.geometryLine = "AB mis #\(self.eventCount) | \(actual)/\(target)pt | rows \(rows)"
    self.appendEvent(event)
  }

  func recordAction(_ action: KeyboardLiveDebugAction) {
    if action == .swipeMoving {
      self.swipeMoveCount &+= 1
      // Show swipe progress without processing every sample on the UI thread.
      guard self.swipeMoveCount % 6 == 0 else { return }
      self.appendEvent("swipe.move x\(self.swipeMoveCount)")
      return
    }
    if action == .swipeCommitted { self.swipeMoveCount = 0 }
    self.appendEvent(action.rawValue)
  }

  private func appendEvent(_ name: String) {
    self.eventCount &+= 1
    let seconds = max(0, CFAbsoluteTimeGetCurrent() - self.startedAt)
    self.events.append(String(format: "+%.2fs %@", seconds, name))
    if self.events.count > 2 { self.events.removeFirst(self.events.count - 2) }
    let now = CFAbsoluteTimeGetCurrent()
    if now - self.lastPaintAt >= 0.10 {
      self.paint(at: now)
    } else if !self.paintPending {
      self.paintPending = true
      DispatchQueue.main.asyncAfter(deadline: .now() + 0.10) { [weak self] in
        guard let self else { return }
        self.paintPending = false
        self.paint(at: CFAbsoluteTimeGetCurrent())
      }
    }
  }

  private func paint(at now: CFAbsoluteTime) {
    self.lastPaintAt = now
    self.label.text = ([self.geometryLine, self.stateLine] + Array(self.events.suffix(2))).joined(separator: "\n")
  }
}
#endif
