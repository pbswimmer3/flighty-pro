import SwiftUI

/// Small colored capsule used for flight status, risk ratings, flight
/// categories (VFR/IFR), etc.
struct StatusPill: View {
    let text: String
    let color: Color
    var filled: Bool = true
    /// The headline pill on a screen (e.g. connection risk). Bigger type
    /// rather than a `scaleEffect`, which rasterises the text.
    var large: Bool = false

    var body: some View {
        Text(text.uppercased())
            .scaledFont(large ? 13 : 11, weight: .heavy)
            .kerning(0.6)
            .padding(.horizontal, large ? 14 : 10)
            .padding(.vertical, large ? 7 : 5)
            .background(filled ? color.opacity(0.18) : Color.clear)
            .foregroundStyle(color)
            .overlay(
                Capsule().strokeBorder(color.opacity(filled ? 0 : 0.6), lineWidth: 1)
            )
            .clipShape(Capsule())
            // The original casing: VoiceOver spells out letter-spaced caps.
            .accessibilityLabel(text)
    }
}

#Preview {
    VStack(spacing: 12) {
        StatusPill(text: "On Time", color: Theme.green)
        StatusPill(text: "Late 45 min", color: Theme.orange)
        StatusPill(text: "Cancelled", color: Theme.red)
        StatusPill(text: "En Route", color: Theme.accent)
        StatusPill(text: "Low risk", color: Theme.green, large: true)
    }
    .padding()
    .background(Theme.background)
}
