import SwiftUI

/// Screenshot-traced iOS-style Emoji key face. The eyes and grin are actual
/// transparent cutouts: in light appearance the same shape renders black.
struct NativeEmojiGlyph: Shape {
  func path(in rect: CGRect) -> Path {
    let unit = min(rect.width, rect.height) / 56
    let ox = rect.midX - 28 * unit
    let oy = rect.midY - 28 * unit

    func point(_ x: CGFloat, _ y: CGFloat) -> CGPoint {
      CGPoint(x: ox + x * unit, y: oy + y * unit)
    }

    var path = Path()
    path.addEllipse(in: CGRect(x: ox - 0.2 * unit, y: oy - 0.2 * unit,
                               width: 56.4 * unit, height: 56.4 * unit))
    path.addEllipse(in: CGRect(x: ox + 16.6 * unit, y: oy + 16.85 * unit,
                               width: 5.7 * unit, height: 7.6 * unit))
    path.addEllipse(in: CGRect(x: ox + 33.8 * unit, y: oy + 16.85 * unit,
                               width: 5.7 * unit, height: 7.6 * unit))

    path.move(to: point(10.4, 29.9))
    path.addCurve(to: point(12.6, 29.0),
                  control1: point(10.0, 28.7), control2: point(11.1, 28.2))
    path.addCurve(to: point(43.5, 29.4),
                  control1: point(21.2, 33.2), control2: point(34.2, 33.6))
    path.addCurve(to: point(46.2, 31.6),
                  control1: point(45.0, 28.4), control2: point(46.7, 28.8))
    path.addCurve(to: point(28.0, 46.7),
                  control1: point(45.2, 41.3), control2: point(38.3, 46.7))
    path.addCurve(to: point(10.4, 31.4),
                  control1: point(17.8, 46.7), control2: point(11.2, 41.5))
    path.closeSubpath()

    path.move(to: point(13.0, 32.6))
    path.addCurve(to: point(43.0, 32.6),
                  control1: point(21.5, 35.8), control2: point(34.3, 36.6))
    path.addCurve(to: point(41.1, 35.7),
                  control1: point(42.9, 34.0), control2: point(42.3, 35.0))
    path.addCurve(to: point(14.7, 35.1),
                  control1: point(33.6, 38.6), control2: point(22.3, 38.5))
    path.addCurve(to: point(13.0, 32.6),
                  control1: point(13.8, 34.7), control2: point(13.3, 33.6))
    path.closeSubpath()
    return path
  }
}
