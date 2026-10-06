import SwiftUI

/// The aircraft symbol shared by every map that draws traffic.
///
/// Lives on its own because three different maps draw it — the airport traffic
/// view, the flight map header and the flight tracking view — and a symbol that
/// drifts apart between them reads as three different apps.
enum AircraftGlyph {

    /// Airliner silhouette in a normalised box, nose at the top (0, -1).
    ///
    /// Only the right half is listed; `path(size:)` mirrors it, which is the
    /// only way to guarantee the wings stay symmetric. A plain triangle was
    /// what this used to be, and at any zoom past "dot on a map" it read as a
    /// generic marker rather than an aircraft — the swept wing and the
    /// tailplane are what make it legible as one.
    ///
    /// Proportions are roughly airliner-like (span ≈ length) but with the span
    /// pulled in a little: at map scale a true 1:1 silhouette is mostly wing,
    /// and neighbouring targets start overlapping wingtips.
    private static let halfOutline: [CGPoint] = [
        CGPoint(x: 0.00, y: -1.00),   // nose
        CGPoint(x: 0.085, y: -0.60),  // forward fuselage
        CGPoint(x: 0.11, y: -0.10),   // wing root, leading edge
        CGPoint(x: 0.78, y:  0.30),   // wing tip, leading edge
        CGPoint(x: 0.78, y:  0.44),   // wing tip, trailing edge
        CGPoint(x: 0.14, y:  0.30),   // wing root, trailing edge
        CGPoint(x: 0.11, y:  0.64),   // aft fuselage
        CGPoint(x: 0.34, y:  0.88),   // stabiliser tip, leading edge
        CGPoint(x: 0.34, y:  0.99),   // stabiliser tip, trailing edge
        CGPoint(x: 0.09, y:  0.90),   // stabiliser root
        CGPoint(x: 0.07, y:  1.00),   // tail cone
    ]

    /// The silhouette pointing at 0° (north), sized so the fuselage is `2 * s`
    /// long. Rotate to heading at draw time.
    static func path(size s: CGFloat) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: halfOutline[0].x * s, y: halfOutline[0].y * s))
        for point in halfOutline.dropFirst() {
            path.addLine(to: CGPoint(x: point.x * s, y: point.y * s))
        }
        // Back up the left side. Dropping the nose keeps `closeSubpath` from
        // drawing a zero-length segment over it.
        for point in halfOutline.dropFirst().reversed() {
            path.addLine(to: CGPoint(x: -point.x * s, y: point.y * s))
        }
        path.closeSubpath()
        return path
    }

    /// Draw one aircraft. When `hasHeading` is false an unoriented dot is drawn
    /// instead of a rotated silhouette — pointing a symbol somewhere is a
    /// claim, and we only make it when the report actually carries a heading.
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
            // The dark outline is what separates a pale aircraft from pale
            // terrain; it scales with the symbol so small targets don't turn
            // into a solid blob of stroke.
            layer.stroke(path, with: .color(.black.opacity(0.55)),
                         lineWidth: max(style.size * 0.07, 0.5))
            if style.isOwn {
                layer.stroke(path, with: .color(.white), lineWidth: 1.5)
            }
        }
    }

    /// The tapped aircraft's callout: identifier on top, route underneath.
    ///
    /// Shared for the same reason the symbol is — the flight tracking map and
    /// the airport traffic map both answer a tap this way, and a callout that
    /// looked different between them would read as two different apps.
    ///
    /// `point` is the top edge of the pill; pass the symbol's screen position
    /// plus its radius. `width` is the canvas width, used to keep a pill near
    /// the edge from being clipped.
    static func drawCallout(_ context: inout GraphicsContext,
                            at point: CGPoint,
                            title: String,
                            subtitle: String?,
                            width: CGFloat) {
        let resolvedTitle = context.resolve(Text(title)
            .font(.system(size: 12, weight: .heavy, design: .rounded))
            .foregroundStyle(.white))
        let resolvedSubtitle = subtitle.map {
            context.resolve(Text($0)
                .font(.system(size: 11, weight: .bold, design: .rounded))
                .foregroundStyle(Color.white.opacity(0.78)))
        }

        let limit = CGSize(width: 240, height: 40)
        let titleSize = resolvedTitle.measure(in: limit)
        let subtitleSize = resolvedSubtitle?.measure(in: limit) ?? .zero
        let contentWidth = max(titleSize.width, subtitleSize.width)
        let contentHeight = titleSize.height + (resolvedSubtitle == nil ? 0 : subtitleSize.height + 2)

        let padX: CGFloat = 8, padY: CGFloat = 5
        let boxWidth = contentWidth + padX * 2
        let clampedX = min(max(point.x, boxWidth / 2 + 6), max(width - boxWidth / 2 - 6, boxWidth / 2 + 6))
        let box = CGRect(x: clampedX - boxWidth / 2,
                         y: point.y,
                         width: boxWidth,
                         height: contentHeight + padY * 2)

        context.fill(Path(roundedRect: box, cornerRadius: 8, style: .continuous),
                     with: .color(.black.opacity(0.78)))
        context.draw(resolvedTitle, at: CGPoint(x: box.midX, y: box.minY + padY), anchor: .top)
        if let resolvedSubtitle {
            context.draw(resolvedSubtitle,
                         at: CGPoint(x: box.midX, y: box.minY + padY + titleSize.height + 2),
                         anchor: .top)
        }
    }
}
