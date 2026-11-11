import SwiftUI

/// The one-time first-run sheet, presented from `MyFlightsView`.
///
/// A fresh install opens on a sample trip, and a tester who isn't told so
/// takes "DL 482, late 14 min" for a real flight. This says what the app does,
/// that the flights behind it are made up, and the two ways to get real ones —
/// manual entry (no key needed) and an AeroDataBox key.
struct WelcomeView: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                VStack(spacing: 12) {
                    Image(systemName: "airplane.circle.fill")
                        .scaledFont(72, design: .default)
                        .foregroundStyle(Theme.accent)
                        .accessibilityHidden(true)
                    Text("Welcome to Flight Dash")
                        .scaledFont(28, weight: .heavy)
                        .multilineTextAlignment(.center)
                        .accessibilityAddTraits(.isHeader)
                    Text("Live tracking, arrival forecasts and a lifetime Passport for the flights you take.")
                        .scaledFont(15, weight: .medium)
                        .foregroundStyle(Theme.textSecondary)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.top, 12)

                VStack(alignment: .leading, spacing: 18) {
                    featureRow(icon: "airplane",
                               title: "Track your flight",
                               detail: "Gates, delays, the aircraft on a map, and a countdown to boarding.")
                    featureRow(icon: "chart.line.uptrend.xyaxis",
                               title: "See it coming",
                               detail: "A forecast of how late you'll land, with its reasons shown.")
                    featureRow(icon: "book.closed.fill",
                               title: "Keep a Passport",
                               detail: "Miles, hours, airports and every minute lost to delays, built from your flights.")
                }

                sampleTripCard

                Button {
                    dismiss()
                } label: {
                    Text("Explore the sample trip")
                        .scaledFont(17, weight: .heavy)
                        .foregroundStyle(.black)
                        .frame(maxWidth: .infinity, minHeight: 50)
                        .background(Theme.accent, in: Capsule())
                        .contentShape(Capsule())
                }
                .buttonStyle(.plain)
            }
            .padding(24)
        }
        .background(Theme.background)
        .presentationDragIndicator(.visible)
        .preferredColorScheme(.dark)
    }

    private func featureRow(icon: String, title: String, detail: String) -> some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: icon)
                .scaledFont(16, weight: .bold, design: .default)
                .foregroundStyle(Theme.accent)
                .frame(minWidth: 36, minHeight: 36)
                .background(Theme.cardElevated,
                            in: RoundedRectangle(cornerRadius: Theme.radiusChip, style: .continuous))
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .scaledFont(15, weight: .heavy)
                Text(detail)
                    .scaledFont(13, weight: .medium)
                    .foregroundStyle(Theme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .accessibilityElement(children: .combine)
    }

    /// Same tint and shape as `DemoBanner`, so the two read as one thing when
    /// the banner turns up on the Flights tab behind this sheet.
    private var sampleTripCard: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "wand.and.stars")
                .scaledFont(14, weight: .bold, design: .default)
                .foregroundStyle(Theme.sample)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 4) {
                Text("You're starting with a sample trip")
                    .scaledFont(14, weight: .bold)
                    .foregroundStyle(Theme.sample)
                Text("Demo Mode is on, so the flights you'll see are made up. Airport status, weather and live aircraft are always real. Add your own flights any time with *Add Flight → Add your real flight*; for live lookups by flight number, add a free AeroDataBox key in Settings.")
                    .scaledFont(13, weight: .medium)
                    .foregroundStyle(Theme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.sample.opacity(0.12),
                    in: RoundedRectangle(cornerRadius: Theme.radiusInner, style: .continuous))
        .accessibilityElement(children: .combine)
    }
}

#Preview {
    WelcomeView()
}
