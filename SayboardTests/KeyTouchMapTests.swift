import Foundation
import Testing

@Suite("Native-style keyboard hit cells")
struct KeyTouchMapTests {
  @Test func allPositionsInsideRowRouteToExactlyOneKey() {
    for n in [7, 9, 10] {
      let w = 390.0
      for x in stride(from: 0.0, through: w, by: 0.5) {
        let index = KeyTouchMap.keyIndex(at: x, width: w, keyCount: n, horizontalInset: 6.67)
        #expect(index != nil)
        if let index { #expect(index >= 0 && index < n) }
      }
    }
  }

  @Test func predictionCannotSwallowAnotherKeyCenter() {
    let n = 10
    let width = 390.0
    let baseline = KeyTouchMap.boundaries(width: width, keyCount: n, horizontalInset: 6.67)
    let boosted = KeyTouchMap.boundaries(
      width: width, keyCount: n, horizontalInset: 6.67,
      weights: [0,0,1,0,0,0,0,0,0,0], calibrations: [0,0,0.12]
    )
    let cell = (width-13.34)/Double(n)
    for i in 1..<n {
      #expect(abs(boosted[i] - baseline[i]) <= cell * 0.18 + 0.0001)
    }
  }

  @Test func usesOnlySupportedOfflineNextLetters() {
    let weights = KeyTouchPrediction.weights(
      typed: "hel", completions: ["hello", "help"], row: ["l","p","q"]
    )
    #expect(weights[0] > 0)
    #expect(weights[1] > 0)
    #expect(weights[2] == 0)
  }
}
