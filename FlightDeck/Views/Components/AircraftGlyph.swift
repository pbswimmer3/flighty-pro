import SwiftUI

/// The aircraft symbol shared by every map that draws traffic.
///
/// Lives on its own because two different maps draw it — the airport traffic
/// view and the flight tracking view — and a symbol that drifts apart between
/// them reads as two different apps.
enum AircraftGlyph {

    /// A delta pointing at 0° (north). Rotate to heading at draw time.
    static func path(size s: CGFloat) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: 0, y: -s))
        path.addLine(to: CGPoint(x: s * 0.62, y: s * 0.75))
        path.addLine(to: CGPoint(x: 0, y: s * 0.35))
        path.addLine(to: CGPoint(x: -s * 0.62, y: s * 0.75))
        path.closeSubpath()
        return path
    }

    /// Draw one aircraft. When `hasHeading` is false an unoriented dot is drawn
    /// instead of a rotated delta — pointing a symbol somewhere is a claim, and
    /// we only make it when the report actually carries a heading.
    static func draw(_ context: inout GraphicsContext,
                     at point: CGPoint,
                     heading: Double,
                     hasHeading: Bool,
                     style: TrafficSymbol,
                     isSelected: Bool = false) {
        context.drawLayer { layer in
            layer.translateBy(x: point.x, y: point.y)
            layer.opacity = style.opacity

            if isSelected {
                let r = style.size * 1.9
                layer.stroke(Path(ellipseIn: CGRect(x: -r, y: -r, width: r * 2, height: r * 2)),
                             with: .color(.white.opacity(0.9)),
                             lineWidth: 1.5)
            }

            guard hasHeading else {
                let r = style.size * 0.45
                layer.fill(Path(ellipseIn: CGRect(x: -r, y: -r, width: r * 2, height: r * 2)),
                           with: .color(style.color))
                return
            }

            layer.rotate(by: .degrees(heading))
            let path = Self.path(size: style.size)
            layer.fill(path, with: .color(style.color))
            layer.stroke(path, with: .color(.black.opacity(0.55)), lineWidth: 0.75)
            if style.isOwn {
                layer.stroke(path, with: .color(.white), lineWidth: 1.5)
            }
        }
    }
}
