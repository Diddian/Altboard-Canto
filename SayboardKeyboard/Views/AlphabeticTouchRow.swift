import SwiftUI
import UIKit

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
  let adaptiveTouchEnabled: Bool
  let swipeEnabled: Bool
  let swipeArrangement: LetterKeyArrangement
  let swipeRowIndex: Int
  let onSwipe: ([String]) -> Void
  /// Render-only path callback; UIKit stays the sole touch owner.
  let onSwipePath: ([LatinSwipePoint]) -> Void
  let onInsert: (String) -> Void

  @State private var activeIndex: Int?
  @State private var releasedHighlightIndex: Int?
  @State private var releaseHighlightTask: Task<Void, Never>?
  @State private var showingAlternates = false
  @State private var alternateIndex = 0
  @State private var initialX: CGFloat = 0
  @State private var holdTask: Task<Void, Never>?
  @State private var swipeSession = LatinSwipeSession()
  @State private var isGliding = false
  @State private var trailUpdateCount = 0

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
            secondarySymbol: LetterKeySecondary.symbol(row: self.swipeRowIndex, index: index) ?? "",
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
            weights: weights,
            calibrations: self.adaptiveTouchEnabled
              ? KeyboardExperimentMetrics.calibration(
                  row: self.swipeRowIndex, keyCount: self.letters.count
                ) : []
          )
          .allowsHitTesting(false)
        }
      }
      .overlay {
        // UIKit reports finger-down immediately; SwiftUI DragGesture.onChanged
        // can wait for gesture recognition, making quick taps feel unpressed.
        ImmediateKeyTouchSurface(
          onBegan: { point in
            self.beginTouch(at: point, width: geometry.size.width, weights: weights)
          },
          onMoved: { point, start in
            self.moveTouch(at: point, startingAt: start,
                           width: geometry.size.width, weights: weights)
          },
          onEnded: { point in
            self.finishTouch(at: point, width: geometry.size.width, weights: weights)
          },
          onCancelled: {
            KeyboardExperimentMetrics.recordGesture(
              points: self.swipeSession.points.count,
              trailUpdates: self.trailUpdateCount, matches: 0, reason: "cancelled"
            )
            KeyboardTouchLearning.shared.invalidate()
            self.onSwipePath([])
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
      self.onSwipePath([])
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
      weights: weights,
      calibrations: self.adaptiveTouchEnabled
        ? KeyboardExperimentMetrics.calibration(
            row: self.swipeRowIndex, keyCount: self.letters.count
          ) : []
    )
  }

  private func swipeWidth(for rowWidth: CGFloat) -> Double {
    if self.swipeRowIndex == 2 {
      return Double(rowWidth
        + (2 * (KeyboardLayoutGeometry.alphabetSpecialRowInset + 50
          + KeyboardLayoutGeometry.alphabetSpecialGap)).kbScaled)
    }
    return Double(rowWidth)
  }

  private func swipePoint(_ local: CGPoint) -> LatinSwipePoint {
    let xOffset: CGFloat = self.swipeRowIndex == 2
      ? (KeyboardLayoutGeometry.alphabetSpecialRowInset + 50
        + KeyboardLayoutGeometry.alphabetSpecialGap).kbScaled : 0
    let key = KeyboardChromeMetrics.keyHeight
    let gap = KeyboardLayoutGeometry.alphabetRowSpacing.kbScaled
    let yOffset: CGFloat = self.swipeRowIndex == 0 ? 0
      : self.swipeRowIndex == 1 ? key + gap / 2
      : 2 * key + 1.5 * gap
    return LatinSwipePoint(x: Double(local.x + xOffset),
                           y: Double(local.y + yOffset))
  }

  private func beginTouch(at point: CGPoint, width: CGFloat, weights: [Double]) {
    self.trailUpdateCount = 0
    self.onSwipePath([])
    self.reset()
    if self.swipeEnabled {
      self.swipeSession.begin(
        self.swipePoint(point), arrangement: self.swipeArrangement,
        width: self.swipeWidth(for: width)
      )
    }
    self.handleTouch(at: point.x, startingAt: point.x, width: width, weights: weights)
  }

  private func moveTouch(
    at point: CGPoint, startingAt start: CGPoint,
    width: CGFloat, weights: [Double]
  ) {
    if self.swipeEnabled && !self.showingAlternates {
      self.swipeSession.append(
        self.swipePoint(point), arrangement: self.swipeArrangement,
        width: self.swipeWidth(for: width)
      )
      if LatinSwipeDecoder.gestureLength(self.swipeSession.points) >= 16 {
        // No new gesture recognizer. The already captured UIKit points draw
        // into a noninteractive Canvas above the three letter rows.
        self.onSwipePath(self.swipeSession.points)
        self.trailUpdateCount += 1
      }
      if self.isGliding || self.swipeSession.isLikelyGlide {
        self.isGliding = true
        KeyboardTouchLearning.shared.invalidate()
        self.holdTask?.cancel()
        self.activeIndex = nil
        return
      }
    }
    self.handleTouch(at: point.x, startingAt: start.x, width: width, weights: weights)
  }

  private func finishTouch(at point: CGPoint, width: CGFloat, weights: [Double]) {
    self.onSwipePath([])
    if self.isGliding {
      self.swipeSession.append(
        self.swipePoint(point), arrangement: self.swipeArrangement,
        width: self.swipeWidth(for: width)
      )
      let preferred = LatinWordSuggestionPolicy.preferredCodes(
        SharedSettings().preferredSpokenLanguages
      )
      let codes = preferred.filter { $0 == "en" || $0 == "de" }
      let languages = codes.isEmpty ? ["en", "de"] : codes
      // Full JBoard frequency corpus is bundled offline for English.
      // Keep learned explicit choices and the deterministic small starter list.
      let learned = LatinWordSuggestions.shared.learnedSwipeWords(preferred: languages)
      let corpus = languages.contains("en")
        ? SwipeWordLexicon.shared.nearbyWords(
            path: self.swipeSession.points, arrangement: self.swipeArrangement,
            fullWidth: self.swipeWidth(for: width)
          ) : []
      let dictionary = learned + corpus
        + languages.flatMap { LatinWordSuggestions.commonWords[$0] ?? [] }
      let matches = LatinSwipeDecoder.rank(
        path: self.swipeSession.points, arrangement: self.swipeArrangement,
        fullWidth: self.swipeWidth(for: width), words: dictionary
      )
      KeyboardExperimentMetrics.recordGesture(
        points: self.swipeSession.points.count,
        trailUpdates: self.trailUpdateCount, matches: matches.count,
        reason: matches.isEmpty ? "no-candidate" : "matched"
      )
      self.reset()
      if !matches.isEmpty {
        self.onSwipe(matches)
      }
      return
    }
    self.endTouch(at: point.x, width: width, weights: weights)
    self.swipeSession.reset()
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
      self.alternateIndex = LetterHoldNavigation.selectedIndex(
        initialX: Double(self.initialX), currentX: Double(x),
        expandsLeft: LetterHoldNavigation.expandsLeft(
          column: index, keyCount: self.letters.count
        ),
        count: self.options(for: index).count, step: Double(32.kbScaled)
      )
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
    let options = self.options(for: index)
    let output: String
    if self.showingAlternates, !options.isEmpty {
      output = options[min(self.alternateIndex, options.count - 1)]
    } else {
      // The held popup has no base character; normal taps still insert it.
      output = self.uppercase
        ? self.letters[index].uppercased() : self.letters[index].lowercased()
    }
    if self.showingAlternates {
      // A held symbol/accent is intentional, not an accidental letter tap.
      KeyboardTouchLearning.shared.invalidate()
    } else {
      KeyboardTouchLearning.shared.recordTap(
        row: self.swipeRowIndex, index: index, keyCount: self.letters.count,
        x: Double(x), width: Double(width), inset: Double(self.horizontalInset),
        enabled: self.adaptiveTouchEnabled
      )
    }
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

  private func options(for index: Int) -> [String] {
    LetterKeyAlternates.holdChoices(
      for: self.letters[index], uppercase: self.uppercase,
      secondary: LetterKeySecondary.symbol(row: self.swipeRowIndex, index: index)
    )
  }

  private func scheduleAlternates(for index: Int) {
    self.holdTask?.cancel()
    guard !self.options(for: index).isEmpty else { return }
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
    self.isGliding = false
    self.swipeSession.reset()
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
  let calibrations: [Double]

  var body: some View {
    Canvas { context, size in
      let boundaries = KeyTouchMap.boundaries(
        width: Double(size.width), keyCount: self.count,
        horizontalInset: Double(self.horizontalInset), weights: self.weights,
        calibrations: self.calibrations
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

private final class ImmediateKeyTouchView: UIView {
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
