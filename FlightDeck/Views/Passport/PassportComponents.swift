import SwiftUI

/// A headline number with a caption and an optional footnote — the Passport's
/// basic unit. Deliberately larger and airier than `StatBlock`, which exists
/// for dense gate/terminal rows.
struct PassportTile: View {
    let value: String
    let caption: String
    var footnote: String?
    var systemImage: String?
    var color: Color = Theme.textPrimary

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            if let systemImage {
                Image(systemName: systemImage)
                    .scaledFont(13, weight: .bold, design: .default)
                    .foregroundStyle(color.opacity(0.85))
                    .accessibilityHidden(true)
            }
            Text(value)
                .scaledFont(27, weight: .heavy)
                .monospacedDigit()
                .foregroundStyle(color)
                .lineLimit(1)
                .minimumScaleFactor(0.5)
            Text(caption.uppercased())
                .scaledFont(11, weight: .bold)
                .kerning(0.8)
                .foregroundStyle(Theme.textTertiary)
            if let footnote {
                Text(footnote)
                    .scaledFont(11, weight: .medium)
                    .foregroundStyle(Theme.textSecondary)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(Theme.cardElevated)
        .clipShape(RoundedRectangle(cornerRadius: Theme.radiusCard, style: .continuous))
        .accessibilityElement(children: .combine)
    }
}

/// A ranked row with a proportional bar behind it — "you flew this 12 times",
/// where the bar is relative to the top entry rather than to the total, so the
/// shape of the list is readable at a glance.
struct RankRow: View {
    let rank: Int
    let title: String
    var subtitle: String?
    let count: Int
    let maxCount: Int
    var unit: String = "flights"
    var tint: Color = Theme.accent

    private var fraction: Double {
        maxCount <= 0 ? 0 : min(Double(count) / Double(maxCount), 1)
    }

    var body: some View {
        HStack(spacing: 12) {
            Text("\(rank)")
                .scaledFont(12, weight: .semibold, design: .monospaced)
                .foregroundStyle(Theme.textTertiary)
                .frame(width: 18, alignment: .trailing)

            VStack(alignment: .leading, spacing: 5) {
                HStack(alignment: .firstTextBaseline) {
                    Text(title)
                        .scaledFont(14, weight: .heavy)
                        .foregroundStyle(Theme.textPrimary)
                        .lineLimit(1)
                    Spacer(minLength: 8)
                    Text("\(count) \(count == 1 ? String(unit.dropLast()) : unit)")
                        .scaledFont(12, weight: .bold)
                        .monospacedDigit()
                        .foregroundStyle(tint)
                        .fixedSize()
                }
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Capsule().fill(Color.white.opacity(0.07))
                        Capsule().fill(tint.opacity(0.75))
                            .frame(width: max(geo.size.width * fraction, 3))
                    }
                }
                .frame(height: 4)
                .accessibilityHidden(true)
                if let subtitle {
                    Text(subtitle)
                        .scaledFont(11, weight: .medium)
                        .foregroundStyle(Theme.textSecondary)
                        .lineLimit(1)
                }
            }
        }
        .padding(.vertical, 7)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilitySummary)
    }

    private var accessibilitySummary: String {
        let countText = "\(count) \(count == 1 ? String(unit.dropLast()) : unit)"
        let base = "\(rank). \(title), \(countText)"
        if let subtitle { return "\(base), \(subtitle)" }
        return base
    }
}

/// A ranked list inside a card, with a "show all" toggle once it gets long.
struct RankedCard: View {
    let title: String
    let systemImage: String
    let rows: [PassportStats.Tally]
    var unit: String = "flights"
    var tint: Color = Theme.accent
    var collapsedCount = 5
    var emptyMessage = "Nothing recorded yet."

    @State private var expanded = false

    private var visible: [PassportStats.Tally] {
        expanded ? rows : Array(rows.prefix(collapsedCount))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            SectionHeader(title: title, systemImage: systemImage)
                .padding(.bottom, 4)

            if rows.isEmpty {
                Text(emptyMessage)
                    .scaledFont(13, weight: .medium)
                    .foregroundStyle(Theme.textSecondary)
                    .padding(.vertical, 6)
            } else {
                let top = rows.first?.count ?? 1
                ForEach(Array(visible.enumerated()), id: \.element.id) { index, tally in
                    RankRow(rank: index + 1,
                            title: tally.label,
                            subtitle: tally.detail,
                            count: tally.count,
                            maxCount: top,
                            unit: unit,
                            tint: tint)
                }
                if rows.count > collapsedCount {
                    Button {
                        withAnimation(.easeInOut(duration: 0.2)) { expanded.toggle() }
                    } label: {
                        Text(expanded ? "Show less" : "Show all \(rows.count)")
                            .scaledFont(13, weight: .bold)
                            .foregroundStyle(Theme.accent)
                            .frame(minHeight: 44)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .padding(.top, 4)
                }
            }
        }
        .cardStyle()
    }
}

/// Seven bars, Sunday through Saturday. Small enough to sit inside a card and
/// still answer "when do I actually fly?".
struct WeekdayChart: View {
    let histogram: [Int]
    /// Sunday-first, matching `PassportStats.weekdayHistogram[0]`.
    private let labels = Calendar.current.shortWeekdaySymbols

    private var summary: String {
        "Departures by day of week: " + zip(Calendar.current.weekdaySymbols, histogram)
            .map { "\($0) \($1)" }
            .joined(separator: ", ")
    }

    private var peak: Int { max(histogram.max() ?? 0, 1) }

    var body: some View {
        HStack(alignment: .bottom, spacing: 8) {
            ForEach(0..<7, id: \.self) { index in
                let count = index < histogram.count ? histogram[index] : 0
                VStack(spacing: 5) {
                    Text(count > 0 ? "\(count)" : "")
                        .scaledFont(11, weight: .bold)
                        .monospacedDigit()
                        .foregroundStyle(Theme.textTertiary)
                    RoundedRectangle(cornerRadius: 4, style: .continuous)
                        .fill(count == peak && count > 0 ? Theme.accent : Theme.accent.opacity(0.32))
                        .frame(height: max(CGFloat(count) / CGFloat(peak) * 60, 3))
                    Text(labels[index])
                        .scaledFont(11, weight: .bold)
                        .foregroundStyle(Theme.textSecondary)
                }
                .frame(maxWidth: .infinity)
            }
        }
        .frame(height: 92, alignment: .bottom)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(summary)
    }
}

/// Horizontal chip strip used for the Passport's year picker.
struct ScopePicker: View {
    let scopes: [PassportStats.Scope]
    @Binding var selection: PassportStats.Scope

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(scopes) { scope in
                    let isSelected = scope == selection
                    Button {
                        withAnimation(.easeInOut(duration: 0.15)) { selection = scope }
                    } label: {
                        Text(scope.label)
                            .scaledFont(13, weight: .heavy)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 8)
                            .background(isSelected ? Theme.accent.opacity(0.22) : Theme.cardElevated)
                            .foregroundStyle(isSelected ? Theme.accent : Theme.textSecondary)
                            .clipShape(Capsule())
                            .overlay(Capsule().strokeBorder(isSelected ? Theme.accent.opacity(0.6) : .clear, lineWidth: 1))
                            .frame(minHeight: 44)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(isSelected ? .isSelected : [])
                }
            }
            .padding(.horizontal, 4)
        }
    }
}

// MARK: - Passport formatting

extension Fmt {
    /// "12,480" — thousands separators for the big Passport numbers.
    static func grouped(_ value: Int) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.maximumFractionDigits = 0
        return formatter.string(from: NSNumber(value: value)) ?? "\(value)"
    }

    static func grouped(_ value: Double) -> String { grouped(Int(value.rounded())) }

    /// "1,204 h" for totals that would be absurd in hours-and-minutes.
    static func longDuration(_ interval: TimeInterval) -> String {
        let hours = Int(interval / 3600)
        let minutes = Int(interval / 60) % 60
        if hours >= 100 { return "\(grouped(hours))h" }
        if hours > 0 { return "\(hours)h \(minutes)m" }
        return "\(minutes)m"
    }

    /// "Mar 2026"
    static func monthAndYear(_ date: Date, tz: TimeZone? = nil) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMM yyyy"
        formatter.timeZone = tz ?? .current
        return formatter.string(from: date)
    }

    /// "12 Mar 2026"
    static func fullDate(_ date: Date, tz: TimeZone? = nil) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "d MMM yyyy"
        formatter.timeZone = tz ?? .current
        return formatter.string(from: date)
    }

    static func percent(_ fraction: Double) -> String {
        "\(Int((fraction * 100).rounded()))%"
    }
}
