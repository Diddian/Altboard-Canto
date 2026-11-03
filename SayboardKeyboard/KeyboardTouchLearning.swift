import Foundation

/// In-memory correction classifier. It never saves taps or typed characters.
/// A boundary shift needs repeated explicit Delete -> adjacent-key repairs.
@MainActor
final class KeyboardTouchLearning {
  static let shared = KeyboardTouchLearning()

  private struct Tap {
    let row: Int
    let index: Int
    let keyCount: Int
    let x: Double
    let width: Double
    let inset: Double
    let at: TimeInterval
  }

  private var pending: Tap?
  private var deletedOnce = false
  private init() {}

  func recordTap(row: Int, index: Int, keyCount: Int, x: Double,
                 width: Double, inset: Double, enabled: Bool) {
    guard enabled else { invalidate(); return }
    let now = Date().timeIntervalSinceReferenceDate
    if let old = pending, deletedOnce, now - old.at <= 2,
       old.row == row, old.keyCount == keyCount,
       abs(old.index - index) == 1 {
      let cell = (old.width - 2 * old.inset) / Double(keyCount)
      let border = old.inset + Double(max(old.index, index)) * cell
      // Ignore deliberate mid-key changes and all non-neighbour repairs.
      if cell > 0, abs(old.x - border) <= cell * 0.38 {
        KeyboardExperimentMetrics.observeAdjacentCorrection(
          row: row, wrong: old.index, corrected: index, keyCount: keyCount
        )
      }
    }
    pending = Tap(row: row, index: index, keyCount: keyCount,
                  x: x, width: width, inset: inset, at: now)
    deletedOnce = false
  }

  func recordDelete() {
    guard let pending,
          Date().timeIntervalSinceReferenceDate - pending.at <= 2,
          !deletedOnce else { invalidate(); return }
    deletedOnce = true
  }

  func invalidate() {
    pending = nil
    deletedOnce = false
  }
}
