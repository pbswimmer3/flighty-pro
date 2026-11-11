import SwiftUI

/// Flighty-style flight progress bar: a track between origin and destination
/// dots with a plane glyph positioned at the current progress.
struct ProgressPlaneBar: View {
    /// 0.0 = at gate, 1.0 = arrived.
    let progress: Double
    var activeColor: Color = Theme.accent
    /// Hidden by default: on a flight card the progress is already in the
    /// card's own spoken label. Pass `false` where the bar stands alone.
    var accessibilityHidden = true

    private var clamped: Double { min(max(progress, 0), 1) }

    var body: some View {
        GeometryReader { geo in
            let width = geo.size.width
            let x = clamped * width

            ZStack(alignment: .leading) {
                Capsule()
                    .fill(Color.white.opacity(0.12))
                    .frame(height: 3)

                Capsule()
                    .fill(activeColor)
                    .frame(width: max(x, 6), height: 3)

                Circle()
                    .fill(activeColor)
                    .frame(width: 7, height: 7)

                Circle()
                    .fill(clamped >= 0.995 ? activeColor : Color.white.opacity(0.25))
                    .frame(width: 7, height: 7)
                    .frame(maxWidth: .infinity, alignment: .trailing)

                Image(systemName: "airplane")
                    .scaledFont(14, weight: .bold, design: .default)
                    .foregroundStyle(.white)
                    .shadow(color: .black.opacity(0.6), radius: 3)
                    .position(x: min(max(x, 10), width - 10), y: geo.size.height / 2)
            }
            .frame(height: geo.size.height)
        }
        .frame(height: 18)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(Int(clamped * 100)) percent of the way")
        .accessibilityHidden(accessibilityHidden)
    }
}

#Preview {
    VStack(spacing: 20) {
        ProgressPlaneBar(progress: 0)
        ProgressPlaneBar(progress: 0.45)
        ProgressPlaneBar(progress: 1, activeColor: Theme.green)
    }
    .padding()
    .background(Theme.background)
}
