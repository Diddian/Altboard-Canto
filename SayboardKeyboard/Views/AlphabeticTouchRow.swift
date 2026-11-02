import SwiftUI

/// A single touch surface for one QWERTY/QWERTZ letter row. The drawn keys
/// have 6pt gaps, but the row has no uncovered touch locations. Press, slide
/// to a neighbor, and long-press accents are coordinated in one gesture.
struct AlphabeticTouchRow: View {
  let letters: [String]
  let uppercase: Bool
  let horizontalInset: CGFloat
  let topHitInset: CGFloat
  let bottomHitInset: CGFloat
  let typedContext: String?
  let completionWords: [String]
  let showTouchDebug: Bool
  let onInsert: (String) -> Void

  @State private var activeIndex: Int?
  @State private var releasedHighlightIndex: Int?
  @State private var releaseHighlightTask: Task<Void, Never>?
  @State private var showingAlternates = false
  @State private var alternateIndex = 0
  @State private var initialX: CGFloat = 0
  @State private var holdTask: Task<Void, Never>?

  private var bandHeight: CGFloat {
    KeyboardChromeMetrics.keyHeight + self.topHitInset + self.bottomHitInset
  }

  var body: some View {
    GeometryReader { geometry in
      let weights = KeyTouchPrediction.weights(
        typed: self.typedContext, completions: self.completionWords, row: self.letters
      )
      HStack(spacing: 0) {
        ForEach(Array(self.letters.enumerated()), id: \.offset) { index, letter in
          AlphabeticLetterKey(
            letter: letter,
            uppercase: self.uppercase,
            column: index,
            rowCount: self.letters.count,
            pressed: self.activeIndex == index || self.releasedHighlightIndex == index,
            choosing: self.activeIndex == index && self.showingAlternates,
            selected: self.alternateIndex
          )
          .frame(maxWidth: .infinity)
          // The UIKit touch surface owns physical taps; VoiceOver needs its
          // own activation path for each underlying visual letter.
          .accessibilityAddTraits(.isButton)
          .accessibilityAction {
            KeyboardHaptics.key()
            self.onInsert(self.uppercase ? letter.uppercased() : letter.lowercased())
          }
        }
      }
      .padding(.horizontal, self.horizontalInset)
      .padding(.top, self.topHitInset)
      .frame(width: geometry.size.width, height: self.bandHeight, alignment: .top)
      .contentShape(Rectangle())
      .overlay {
        if self.showTouchDebug {
          KeyboardTouchDebugOverlay(
            count: self.letters.count,
            horizontalInset: self.horizontalInset,
            topInset: self.topHitInset,
            keyHeight: KeyboardChromeMetrics.keyHeight,
            weights: weights
          )
          .allowsHitTesting(false)
        }
      }
      .overlay {
        // UIKit reports finger-down immediately; SwiftUI DragGesture.onChanged
        // can wait for gesture recognition, making quick taps feel unpressed.
        ImmediateKeyTouchSurface(
          onBegan: { x in
            self.handleTouch(at: x, startingAt: x,
                             width: geometry.size.width, weights: weights)
          },
          onMoved: { x, startX in
            self.handleTouch(at: x, startingAt: startX,
                             width: geometry.size.width, weights: weights)
          },
          onEnded: { x in
            self.endTouch(at: x, width: geometry.size.width, weights: weights)
          },
          onCancelled: {
            self.reset()
          }
        )
        .frame(width: geometry.size.width, height: self.bandHeight)
        .accessibilityHidden(true)
      }
    }
    .frame(height: self.bandHeight)
    .zIndex(self.activeIndex == nil ? 0 : 10)
    .onDisappear {
      self.releaseHighlightTask?.cancel()
      self.releasedHighlightIndex = nil
      self.reset()
    }
  }

  private func target(at x: CGFloat, width: CGFloat, weights: [Double]) -> Int? {
    KeyTouchMap.keyIndex(
      at: Double(x),
      width: Double(width),
      keyCount: self.letters.count,
      horizontalInset: Double(self.horizontalInset),
      weights: weights
    )
  }

  private func handleTouch(
    at x: CGFloat, startingAt start: CGFloat, width: CGFloat, weights: [Double]
  ) {
    guard !self.letters.isEmpty else { return }
    if self.activeIndex == nil {
      guard let index = self.target(at: start, width: width, weights: weights) else { return }
      self.releaseHighlightTask?.cancel()
      self.releasedHighlightIndex = nil
      self.activeIndex = index
      self.initialX = start
      self.showingAlternates = false
      self.alternateIndex = 0
      KeyboardHaptics.key()
      self.scheduleAlternates(for: index)
    } else if self.showingAlternates, let index = self.activeIndex {
      let trailing = index >= self.letters.count - 3
      let travel = trailing ? self.initialX - x : x - self.initialX
      let choices = LetterKeyAlternates.choices(
        for: self.letters[index], uppercase: self.uppercase
      )
      self.alternateIndex = min(max(0, Int(max(0, travel) / 32.kbScaled)), choices.count - 1)
    } else if let newIndex = self.target(at: x, width: width, weights: weights),
              self.activeIndex != newIndex {
      self.holdTask?.cancel()
      self.activeIndex = newIndex
      self.initialX = x
      KeyboardHaptics.key()
      self.scheduleAlternates(for: newIndex)
    }
  }

  private func endTouch(at x: CGFloat, width: CGFloat, weights: [Double]) {
    guard let active = self.activeIndex else { self.reset(); return }
    let index = self.showingAlternates ? active
      : (self.target(at: x, width: width, weights: weights) ?? active)
    let options = LetterKeyAlternates.choices(
      for: self.letters[index], uppercase: self.uppercase
    )
    let option = self.showingAlternates ? min(self.alternateIndex, options.count - 1) : 0
    let output = options[option]
    self.reset()
    // Keep a very short highlight after quick taps, so SwiftUI can display
    // the pressed face even when down and up occur in the same frame.
    self.releasedHighlightIndex = index
    self.releaseHighlightTask?.cancel()
    self.releaseHighlightTask = Task { @MainActor in
      do { try await Task.sleep(for: .milliseconds(80)) } catch { return }
      guard !Task.isCancelled else { return }
      self.releasedHighlightIndex = nil
    }
    self.onInsert(output)
  }

  private func scheduleAlternates(for index: Int) {
    self.holdTask?.cancel()
    guard LetterKeyAlternates.choices(
      for: self.letters[index], uppercase: self.uppercase
    ).count > 1 else { return }
    self.holdTask = Task { @MainActor in
      do { try await Task.sleep(for: .milliseconds(380)) } catch { return }
      guard !Task.isCancelled, self.activeIndex == index else { return }
      self.showingAlternates = true
      self.alternateIndex = 0
      KeyboardHaptics.key(strength: 0.35)
    }
  }

  private func reset() {
    self.holdTask?.cancel()
    self.holdTask = nil
    self.activeIndex = nil
    self.showingAlternates = false
    self.alternateIndex = 0
  }
}

/// Orange solid = the routed touch cells; teal dashed = the unchanged
/// visible key rectangles. This opt-in overlay never records typed content.
private struct KeyboardTouchDebugOverlay: View {
  let count: Int
  let horizontalInset: CGFloat
  let topInset: CGFloat
  let keyHeight: CGFloat
  let weights: [Double]

  var body: some View {
    Canvas { context, size in
      let boundaries = KeyTouchMap.boundaries(
        width: Double(size.width), keyCount: self.count,
        horizontalInset: Double(self.horizontalInset), weights: self.weights
      )
      guard boundaries.count == self.count + 1 else { return }
      for index in 0..<self.count {
        let hit = CGRect(
          x: CGFloat(boundaries[index]), y: 0,
          width: CGFloat(boundaries[index+1] - boundaries[index]),
          height: size.height
        )
        context.stroke(Path(hit), with: .color(.orange.opacity(0.8)), lineWidth: 1)
        if let visible = KeyTouchMap.visibleKeyBounds(
          width: Double(size.width), keyCount: self.count,
          horizontalInset: Double(self.horizontalInset), index: index
        ) {
          let rect = CGRect(
            x: CGFloat(visible.lowerBound), y: self.topInset,
            width: CGFloat(visible.upperBound - visible.lowerBound), height: self.keyHeight
          )
          context.stroke(
            Path(rect), with: .color(.cyan.opacity(0.85)),
            style: StrokeStyle(lineWidth: 1, dash: [3, 3])
          )
        }
      }
    }
  }
}


/// A direct UIKit touch surface for letter keys. Unlike a drag recognizer,
/// touchesBegan arrives on initial contact, before the finger moves or holds.
/// This has no animations, timers or delayed state transitions.
private struct ImmediateKeyTouchSurface: UIViewRepresentable {
  let onBegan: (CGFloat) -> Void
  let onMoved: (CGFloat, CGFloat) -> Void
  let onEnded: (CGFloat) -> Void
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

private final class ImmediateKeyTouchView: UIView {
  var onBegan: ((CGFloat) -> Void)?
  var onMoved: ((CGFloat, CGFloat) -> Void)?
  var onEnded: ((CGFloat) -> Void)?
  var onCancelled: (() -> Void)?

  private var activeTouch: UITouch?
  private var initialX: CGFloat = 0

  override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
    guard self.activeTouch == nil, let touch = touches.first else { return }
    self.activeTouch = touch
    self.initialX = touch.location(in: self).x
    self.onBegan?(self.initialX)
  }

  override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
    guard let active = self.activeTouch, touches.contains(active) else { return }
    self.onMoved?(active.location(in: self).x, self.initialX)
  }

  override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
    guard let active = self.activeTouch, touches.contains(active) else { return }
    let x = active.location(in: self).x
    self.activeTouch = nil
    self.onEnded?(x)
  }

  override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) {
    guard let active = self.activeTouch, touches.contains(active) else { return }
    self.activeTouch = nil
    self.onCancelled?()
  }
}
