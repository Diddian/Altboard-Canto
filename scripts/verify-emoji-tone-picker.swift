import Foundation

@main
struct EmojiTonePickerChecks {
  static func main() {
    func geometry(
      right: Bool, cellWidth: Double = 44, itemWidth: Double = 36,
      itemHeight: Double = 43, padding: Double = 6, count: Int = 6,
      minY: Double = -60, maxY: Double = 157
    ) -> EmojiTonePickerGeometry {
      EmojiTonePickerGeometry(
        cellWidth: cellWidth, itemWidth: itemWidth, itemHeight: itemHeight,
        padding: padding, itemCount: count, alignRight: right,
        bounds: .init(minX: right ? cellWidth - 320 : 0,
                      maxX: right ? cellWidth : 320, minY: minY, maxY: maxY)
      )
    }

    let left = geometry(right: false)
    let right = geometry(right: true)
    precondition(left.originX == 0 && left.originY == -49)
    precondition(right.originX == -184 && right.originY == -49)
    // Both popovers keep the displayed left-to-right order.
    for (x, index) in zip([24.0, 60, 96, 132, 168, 204], 0..<6) {
      precondition(left.selection(atX: x, y: -21.5) == index)
    }
    for (x, index) in zip([-160.0, -124, -88, -52, -16, 20], 0..<6) {
      precondition(right.selection(atX: x, y: -21.5) == index)
    }
    precondition(right.selection(atX: 20, y: -21.5) == 5)
    precondition(right.selection(atX: -16, y: -21.5) == 4)

    // Unicode mixed-person sequences have up to 26 variants. Every one must
    // remain reachable in the bounded grid, including the incomplete last row.
    let grid = geometry(right: false, itemHeight: 36, count: 26)
    precondition(grid.columns == 6 && grid.rows == 5)
    precondition(grid.popupWidth == 228 && grid.popupHeight == 192)
    precondition(grid.originY == -60)
    for index in 0..<26 {
      let x = 24.0 + Double(index % 6) * 36
      let y = -36.0 + Double(index / 6) * 36
      precondition(grid.selection(atX: x, y: y) == index)
    }
    precondition(grid.selection(atX: 41.999, y: -18.001) == 0)
    precondition(grid.selection(atX: 42, y: -18) == 7)
    precondition(grid.selection(atX: 204, y: 108) == 25)
    precondition(grid.selection(atX: -10_000, y: -10_000) == 0)
    precondition(grid.selection(atX: 10_000, y: 10_000) == 25)

    for scale in [0.75, 1.0, 1.5] {
      for cellWidth in [31.75, 44.0, 62.125] {
        for count in [5, 6, 20, 26] {
          for alignedRight in [false, true] {
            let value = geometry(
              right: alignedRight, cellWidth: cellWidth * scale,
              itemWidth: 36 * scale, itemHeight: 43 * scale,
              padding: 6 * scale, count: count, minY: -172, maxY: 45
            )
            let renderedOrigin = value.cellWidth / 2 - value.popupWidth / 2
              + value.centerOffsetX
            precondition(abs(renderedOrigin - value.originX) < 0.000001)
            precondition(value.originX >= value.bounds.minX - 0.000001)
            precondition(value.originX + value.popupWidth <= value.bounds.maxX + 0.000001)
            precondition(value.originY >= value.bounds.minY - 0.000001)
            precondition(value.originY + value.popupHeight <= value.bounds.maxY + 0.000001)
            for index in 0..<count {
              let x = value.originX + value.padding
                + (Double(index % value.columns) + 0.5) * value.resolvedItemWidth
              let y = value.originY + value.padding
                + (Double(index / value.columns) + 0.5) * value.resolvedItemHeight
              precondition(value.selection(atX: x, y: y) == index)
            }
          }
        }
      }
    }

    precondition(geometry(right: false, count: 0).selection(atX: 0, y: 0) == nil)
    precondition(geometry(right: false, itemWidth: 0).selection(atX: 0, y: 0) == nil)
    precondition(geometry(right: false, cellWidth: .nan).selection(atX: 0, y: 0) == nil)
    precondition(geometry(right: false, padding: -1).selection(atX: 0, y: 0) == nil)
    precondition(left.selection(atX: .nan, y: 0) == nil)
    precondition(left.selection(atX: 0, y: .infinity) == nil)
    print("Emoji tone picker coordinates: PASS")
  }
}
