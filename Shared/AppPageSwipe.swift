/// Page selection only; native child controls retain gesture priority.
enum AppPageSwipe {
  static func destination(
    current: Int, count: Int, startX: Double,
    horizontal: Double, vertical: Double
  ) -> Int? {
    guard current >= 0, current < count, startX > 32,
          abs(horizontal) >= 90, abs(horizontal) > 2 * abs(vertical) else { return nil }
    let next = current + (horizontal < 0 ? 1 : -1)
    return (0..<count).contains(next) ? next : nil
  }
}
