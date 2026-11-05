@main
enum VerifyAppPageSwipe {
  static func main() {
    func destination(_ current: Int, _ x: Double, _ y: Double = 0, start: Double = 100) -> Int? {
      AppPageSwipe.destination(current: current, count: 3, startX: start,
                               horizontal: x, vertical: y)
    }
    precondition(destination(0, -120) == 1)
    precondition(destination(1, -120) == 2)
    precondition(destination(2, 120) == 1)
    precondition(destination(1, 120) == 0)
    precondition(destination(0, 120) == nil)
    precondition(destination(2, -120) == nil)
    precondition(destination(1, -40) == nil)
    precondition(destination(1, -120, 90) == nil)
    precondition(destination(1, -120, start: 10) == nil)
    precondition(destination(-1, -120) == nil)
    print("App page swipe: 10 direction, boundary and gesture checks passed")
  }
}
