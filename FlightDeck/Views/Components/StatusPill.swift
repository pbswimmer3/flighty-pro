import SwiftUI

/// Small colored capsule used for flight status, risk ratings, flight
/// categories (VFR/IFR), etc.
struct StatusPill: View {
    let text: String
    let color: Color
    var filled: Bool = true

    var body: some View {
        Text(text.uppercased())
            .font(.system(size: 11, weight: .heavy, design: .rounded))
            .kerning(0.6)
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(filled ? color.opacity(0.18) : Color.clear)
            .foregroundStyle(color)
            .overlay(
                Capsule().strokeBorder(color.opacity(filled ? 0 : 0.6), lineWidth: 1)
            )
            .clipShape(Capsule())
    }
}

#Preview {
    VStack(spacing: 12) {
        StatusPill(text: "On Time", color: Theme.green)
        StatusPill(text: "Delayed 45m", color: Theme.orange)
        StatusPill(text: "Cancelled", color: Theme.red)
        StatusPill(text: "En Route", color: Theme.accent)
    }
    .padding()
    .background(Theme.background)
}
