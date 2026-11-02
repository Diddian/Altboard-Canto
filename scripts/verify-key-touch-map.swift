import Foundation

@main
struct VerifyKeyTouchMap {
  static func main() {
    let count = 10
    let width = 390.0
    let inset = 6.67
    let edges = KeyTouchMap.boundaries(width: width, keyCount: count, horizontalInset: inset)
    precondition(edges.count == count + 1)
    precondition(edges.first == 0 && edges.last == width)
    for i in 1..<edges.count { precondition(edges[i] > edges[i-1]) }
    for x in stride(from: 0.0, through: width, by: 0.25) {
      precondition(KeyTouchMap.keyIndex(at: x, width: width, keyCount: count,
                                       horizontalInset: inset) != nil)
    }
    precondition(KeyTouchMap.keyIndex(at: -1, width: width, keyCount: count,
                                     horizontalInset: inset) == nil)
    precondition(KeyTouchMap.keyIndex(at: 0, width: width, keyCount: count,
                                     horizontalInset: inset) == 0)
    precondition(KeyTouchMap.keyIndex(at: width, width: width, keyCount: count,
                                     horizontalInset: inset) == count-1)

    var left = Array(repeating: 0.0, count: count)
    left[2] = 1
    let boosted = KeyTouchMap.boundaries(
      width: width, keyCount: count, horizontalInset: inset, weights: left
    )
    precondition(boosted[3] > edges[3])
    let cell = (width - 2 * inset) / Double(count)
    for i in 1..<count {
      precondition(abs(boosted[i]-edges[i]) <= cell * 0.18 + 0.00001)
    }
    let weights = KeyTouchPrediction.weights(
      typed: "hel", completions: ["hello", "help", "helmet"], row: ["l", "p", "x"]
    )
    precondition(weights[0] > weights[2] && weights[1] > weights[2])
    precondition(KeyTouchPrediction.weights(
      typed: nil, completions: ["hello"], row: ["h"]
    ) == [0])
    print("Key touch map: gap coverage, bounding, prediction and edge cases pass")
  }
}
