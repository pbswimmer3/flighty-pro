import SwiftUI

/// The delay tracker in full: how much time you've lost, who took it, and the
/// running list of every delayed arrival.
struct DelayTrackerView: View {
    let stats: PassportStats

    private var delays: PassportStats.DelayStats { stats.delays }

    var body: some View {
        ScrollView {
            VStack(spacing: 14) {
                headline
                if delays.flightsCounted > 0 {
                    breakdown
                }
                RankedCard(title: "Worst Airlines",
                           systemImage: "building.2.crop.circle.badge.clock",
                           rows: delays.byAirline,
                           unit: "delays",
                           tint: Theme.orange,
                           emptyMessage: "No airline has delayed you yet.")
                RankedCard(title: "Worst Airports To Land At",
                           systemImage: "airplane.arrival",
                           rows: delays.byAirport,
                           unit: "delays",
                           tint: Theme.orange,
                           emptyMessage: "No delayed arrivals on record.")
                if !delays.recent.isEmpty {
                    historyCard
                }
                methodology
            }
            .padding(.horizontal)
            .padding(.bottom, 30)
        }
        .background(Theme.background)
        .navigationTitle("Delay Tracker")
        .navigationBarTitleDisplayMode(.inline)
    }

    // MARK: - Headline

    private var headline: some View {
        VStack(spacing: 14) {
            VStack(spacing: 4) {
                Text(Fmt.longDuration(delays.totalDelayInterval))
                    .font(.system(size: 46, weight: .heavy, design: .rounded))
                    .foregroundStyle(delays.totalDelayMinutes > 0 ? Theme.orange : Theme.green)
                    .lineLimit(1)
                    .minimumScaleFactor(0.5)
                Text("LOST TO DELAYS")
                    .font(.system(size: 11, weight: .bold, design: .rounded))
                    .kerning(1.4)
                    .foregroundStyle(Theme.textTertiary)
                Text(scopeLabel)
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .foregroundStyle(Theme.textSecondary)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 10)

            HStack(spacing: 10) {
                PassportTile(value: Fmt.percent(delays.onTimeRate),
                             caption: "On-time rate",
                             footnote: "\(delays.onTimeFlights) of \(delays.flightsCounted) arrivals",
                             systemImage: "checkmark.seal.fill",
                             color: onTimeColor)
                PassportTile(value: "\(delays.averageDelayMinutes)m",
                             caption: "Average delay",
                             footnote: "When a flight is late",
                             systemImage: "clock.fill",
                             color: Theme.orange)
            }
        }
        .cardStyle()
    }

    private var scopeLabel: String {
        switch stats.scope {
        case .allTime: return "Across every flight you've taken"
        case .year(let year): return "During \(year)"
        }
    }

    private var onTimeColor: Color {
        switch delays.onTimeRate {
        case 0.85...: return Theme.green
        case 0.7..<0.85: return Theme.accent
        case 0.5..<0.7: return Theme.orange
        default: return Theme.red
        }
    }

    // MARK: - Breakdown

    private var breakdown: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeader(title: "Breakdown", systemImage: "chart.pie.fill")

            // A single stacked bar reads faster than three separate numbers,
            // and makes the cancelled sliver impossible to miss.
            GeometryReader { geo in
                HStack(spacing: 2) {
                    let total = max(delays.flightsCounted + delays.cancelledFlights, 1)
                    segment(width: geo.size.width * Double(delays.onTimeFlights) / Double(total),
                            color: Theme.green)
                    segment(width: geo.size.width * Double(delays.delayedFlights) / Double(total),
                            color: Theme.orange)
                    segment(width: geo.size.width * Double(delays.cancelledFlights) / Double(total),
                            color: Theme.red)
                }
            }
            .frame(height: 14)

            HStack(spacing: 16) {
                legend(Theme.green, "On time", delays.onTimeFlights)
                legend(Theme.orange, "Delayed", delays.delayedFlights)
                legend(Theme.red, "Cancelled", delays.cancelledFlights)
            }
        }
        .cardStyle()
    }

    private func segment(width: CGFloat, color: Color) -> some View {
        // Zero-width segments would still draw a 2 pt gap; drop them entirely.
        Group {
            if width > 0.5 {
                Capsule().fill(color).frame(width: width)
            }
        }
    }

    private func legend(_ color: Color, _ label: String, _ count: Int) -> some View {
        HStack(spacing: 5) {
            Circle().fill(color).frame(width: 7, height: 7)
            Text("\(label) \(count)")
                .font(.system(size: 12, weight: .semibold, design: .rounded))
                .foregroundStyle(Theme.textSecondary)
        }
    }

    // MARK: - History

    private var historyCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            SectionHeader(title: "Every Delay", systemImage: "list.bullet")
                .padding(.bottom, 8)
            ForEach(delays.recent) { record in
                HStack(spacing: 12) {
                    StatusPill(text: "+\(record.minutes)m", color: severityColor(record.minutes))
                        .frame(width: 76, alignment: .leading)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("\(record.designator) · \(record.route)")
                            .font(.system(size: 14, weight: .bold, design: .rounded))
                        Text(Fmt.fullDate(record.date))
                            .font(.system(size: 11, weight: .medium, design: .rounded))
                            .foregroundStyle(Theme.textSecondary)
                    }
                    Spacer()
                }
                .padding(.vertical, 7)
                if record.id != delays.recent.last?.id {
                    Divider().overlay(Theme.separator)
                }
            }
        }
        .cardStyle()
    }

    private func severityColor(_ minutes: Int) -> Color {
        switch minutes {
        case ..<30: return Theme.orange
        case ..<90: return Color(red: 1.0, green: 0.45, blue: 0.2)
        default: return Theme.red
        }
    }

    // MARK: - Methodology

    private var methodology: some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionHeader(title: "How This Is Counted", systemImage: "info.circle")
            Text("A flight counts as delayed when it arrives \(Flight.delayThresholdMinutes) or more minutes after its scheduled arrival — the same threshold the US Department of Transportation uses, so these numbers line up with published airline statistics.")
                .font(.system(size: 12, weight: .medium, design: .rounded))
                .foregroundStyle(Theme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
            Text("Time lost adds up the arrival delay on those delayed flights only — a flight that landed a few minutes late doesn't count against you, and arriving early doesn't refund an hour you already spent at a gate.")
                .font(.system(size: 12, weight: .medium, design: .rounded))
                .foregroundStyle(Theme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
            Text("Cancellations are tracked separately: they aren't flights you took, so they're excluded from distance, hours and on-time rate.")
                .font(.system(size: 12, weight: .medium, design: .rounded))
                .foregroundStyle(Theme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .cardStyle()
    }
}
