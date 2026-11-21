import Foundation

/// Coordinates are relative to the touched cell. Variant order stays left to right.
struct EmojiTonePickerGeometry: Sendable {
  struct Bounds: Sendable {
    let minX: Double
    let maxX: Double
    let minY: Double
    let maxY: Double
  }

  let cellWidth: Double
  let itemWidth: Double
  let itemHeight: Double
  let padding: Double
  let itemCount: Int
  let alignRight: Bool
  let bounds: Bounds

  var columns: Int { min(6, max(1, self.itemCount)) }
  var rows: Int { max(0, self.itemCount - 1) / self.columns + 1 }
  var resolvedItemWidth: Double {
    min(self.itemWidth, (self.bounds.maxX - self.bounds.minX - 2 * self.padding)
      / Double(self.columns))
  }
  var resolvedItemHeight: Double {
    min(self.itemHeight, (self.bounds.maxY - self.bounds.minY - 2 * self.padding)
      / Double(self.rows))
  }
  var popupWidth: Double { Double(self.columns) * self.resolvedItemWidth + 2 * self.padding }
  var popupHeight: Double { Double(self.rows) * self.resolvedItemHeight + 2 * self.padding }
  var originX: Double {
    let desired = self.alignRight ? self.cellWidth - self.popupWidth : 0
    return max(self.bounds.minX, min(self.bounds.maxX - self.popupWidth, desired))
  }
  var originY: Double {
    max(self.bounds.minY, min(self.bounds.maxY - self.popupHeight, -self.popupHeight + self.padding))
  }
  var centerOffsetX: Double { self.originX + (self.popupWidth - self.cellWidth) / 2 }

  func selection(atX touchX: Double, y touchY: Double) -> Int? {
    guard self.itemCount > 0, self.cellWidth.isFinite, self.cellWidth > 0,
          self.itemWidth.isFinite, self.itemWidth > 0,
          self.itemHeight.isFinite, self.itemHeight > 0,
          self.padding.isFinite, self.padding >= 0,
          self.bounds.minX.isFinite, self.bounds.maxX.isFinite,
          self.bounds.minY.isFinite, self.bounds.maxY.isFinite,
          self.resolvedItemWidth.isFinite, self.resolvedItemWidth > 0,
          self.resolvedItemHeight.isFinite, self.resolvedItemHeight > 0,
          touchX.isFinite, touchY.isFinite else { return nil }
    let row = Int(max(0, min(Double(self.rows - 1),
      floor((touchY - self.originY - self.padding) / self.resolvedItemHeight))))
    let rowStart = row * self.columns
    let lastColumn = min(self.columns, self.itemCount - rowStart) - 1
    let column = Int(max(0, min(Double(lastColumn),
      floor((touchX - self.originX - self.padding) / self.resolvedItemWidth))))
    return rowStart + column
  }
}
