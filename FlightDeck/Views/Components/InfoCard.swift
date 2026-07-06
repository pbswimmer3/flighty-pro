import SwiftUI

/// A labeled key/value row used inside detail cards.
struct InfoRow: View {
    let label: String
    let value: String
    var valueColor: Color = Theme.textPrimary
    var strikethroughValue: String? = nil

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(label)
                .font(.system(size: 14, weight: .medium, design: .rounded))
                .foregroundStyle(Theme.textSecondary)
            Spacer()
            HStack(spacing: 6) {
                if let old = strikethroughValue {
                    Text(old)
                        .strikethrough()
                        .font(.system(size: 14, weight: .medium, design: .rounded))
                        .foregroundStyle(Theme.textTertiary)
                }
                Text(value)
                    .font(.system(size: 15, weight: .bold, design: .rounded))
                    .foregroundStyle(valueColor)
            }
        }
        .padding(.vertical, 2)
    }
}

/// Big stat block: value on top, caption underneath (gate, terminal, etc.).
struct StatBlock: View {
    let caption: String
    let value: String
    var color: Color = Theme.textPrimary

    var body: some View {
        VStack(spacing: 3) {
            Text(value)
                .font(.system(size: 22, weight: .heavy, design: .rounded))
                .foregroundStyle(color)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
            Text(caption.uppercased())
                .font(.system(size: 10, weight: .bold, design: .rounded))
                .kerning(0.8)
                .foregroundStyle(Theme.textTertiary)
        }
        .frame(maxWidth: .infinity)
    }
}

/// Circular airline monogram (Flighty shows airline logos; we render a
/// two-letter carrier code in a colored disc — original, no trademarked art).
struct AirlineBadge: View {
    let code: String
    var size: CGFloat = 40

    private var color: Color {
        // Stable pseudo-random hue per carrier code.
        let hues: [Color] = [Theme.accent, Theme.purple, Theme.cyan,
                             Theme.orange, Theme.green, Color(red: 0.95, green: 0.4, blue: 0.55)]
        let idx = abs(code.unicodeScalars.reduce(0) { $0 &+ Int($1.value) }) % hues.count
        return hues[idx]
    }

    var body: some View {
        ZStack {
            Circle().fill(color.opacity(0.22))
            Text(code)
                .font(.system(size: size * 0.38, weight: .heavy, design: .rounded))
                .foregroundStyle(color)
        }
        .frame(width: size, height: size)
    }
}
