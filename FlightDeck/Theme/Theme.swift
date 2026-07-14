import SwiftUI

/// Central design tokens for the Flighty-style dark look:
/// near-black background, elevated dark cards, saturated status colors,
/// heavy rounded type for airport codes.
enum Theme {
    // MARK: Colors

    static let background = Color(red: 0.043, green: 0.043, blue: 0.059)   // #0B0B0F
    static let card = Color(red: 0.098, green: 0.098, blue: 0.122)         // #19191F
    static let cardElevated = Color(red: 0.137, green: 0.137, blue: 0.169) // #232330
    static let separator = Color.white.opacity(0.08)

    static let accent = Color(red: 0.30, green: 0.56, blue: 1.0)           // Flighty-ish blue
    static let textPrimary = Color.white
    static let textSecondary = Color.white.opacity(0.55)
    static let textTertiary = Color.white.opacity(0.35)

    static let green = Color(red: 0.20, green: 0.84, blue: 0.50)
    static let orange = Color(red: 1.00, green: 0.62, blue: 0.15)
    static let red = Color(red: 1.00, green: 0.28, blue: 0.30)
    static let purple = Color(red: 0.66, green: 0.47, blue: 1.00)
    static let cyan = Color(red: 0.25, green: 0.78, blue: 0.92)

    // MARK: Typography

    /// Big bold airport codes, e.g. "SFO → JFK"
    static func codeFont(_ size: CGFloat) -> Font {
        .system(size: size, weight: .heavy, design: .rounded)
    }

    static func monoFont(_ size: CGFloat, weight: Font.Weight = .semibold) -> Font {
        .system(size: size, weight: weight, design: .monospaced)
    }
}

// MARK: - Card container

struct CardBackground: ViewModifier {
    var padding: CGFloat = 16

    func body(content: Content) -> some View {
        content
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Theme.card)
            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
    }
}

extension View {
    func cardStyle(padding: CGFloat = 16) -> some View {
        modifier(CardBackground(padding: padding))
    }
}

// MARK: - Section header used across screens

struct SectionHeader: View {
    let title: String
    var systemImage: String? = nil

    var body: some View {
        HStack(spacing: 6) {
            if let systemImage {
                Image(systemName: systemImage)
                    .font(.system(size: 12, weight: .bold))
            }
            Text(title.uppercased())
                .font(.system(size: 12, weight: .bold, design: .rounded))
                .kerning(1.2)
            Spacer()
        }
        .foregroundStyle(Theme.textSecondary)
        .padding(.horizontal, 4)
    }
}
