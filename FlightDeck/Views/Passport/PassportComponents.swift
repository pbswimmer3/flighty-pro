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
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(color.opacity(0.85))
            }
            Text(value)
                .font(.system(size: 27, weight: .heavy, design: .rounded))
                .foregroundStyle(color)
                .lineLimit(1)
                .minimumScaleFactor(0.5)
            Text(caption.uppercased())
                .font(.system(size: 10, weight: .bold, design: .rounded))
                .kerning(0.8)
                .foregroundStyle(Theme.textTertiary)
            if let footnote {
                Text(footnote)
                    .font(.system(size: 11, weight: .medium, design: .rounded))
                    .foregroundStyle(Theme.textSecondary)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(Theme.cardElevated)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
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
                .font(Theme.monoFont(12))
                .foregroundStyle(Theme.textTertiary)
                .frame(width: 18, alignment: .trailing)

            VStack(alignment: .leading, spacing: 5) {
                HStack(alignment: .firstTextBaseline) {
                    Text(title)
                        .font(.system(size: 14, weight: .heavy, design: .rounded))
                        .foregroundStyle(Theme.textPrimary)
                        .lineLimit(1)
                    Spacer(minLength: 8)
                    Text("\(count) \(count == 1 ? String(unit.dropLast()) : unit)")
                        .font(.system(size: 12, weight: .bold, design: .rounded))
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
                if let subtitle {
                    Text(subtitle)
                        .font(.system(size: 11, weight: .medium, design: .rounded))
                        .foregroundStyle(Theme.textSecondary)
                        .lineLimit(1)
                }
            }
        }
        .padding(.vertical, 7)
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
                    .font(.system(size: 13, weight: .medium, design: .rounded))
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
                            .font(.system(size: 13, weight: .bold, design: .rounded))
                            .foregroundStyle(Theme.accent)
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
    private let labels = ["S", "M", "T", "W", "T", "F", "S"]

    private var peak: Int { max(histogram.max() ?? 0, 1) }

    var body: some View {
        HStack(alignment: .bottom, spacing: 8) {
            ForEach(0..<7, id: \.self) { index in
                let count = index < histogram.count ? histogram[index] : 0
                VStack(spacing: 5) {
                    Text(count > 0 ? "\(count)" : "")
                        .font(.system(size: 9, weight: .bold, design: .rounded))
                        .foregroundStyle(Theme.textTertiary)
                    RoundedRectangle(cornerRadius: 4, style: .continuous)
                        .fill(count == peak && count > 0 ? Theme.accent : Theme.accent.opacity(0.32))
                        .frame(height: max(CGFloat(count) / CGFloat(peak) * 60, 3))
                    Text(labels[index])
                        .font(.system(size: 10, weight: .bold, design: .rounded))
                        .foregroundStyle(Theme.textSecondary)
                }
                .frame(maxWidth: .infinity)
            }
        }
        .frame(height: 92, alignment: .bottom)
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
                            .font(.system(size: 13, weight: .heavy, design: .rounded))
                            .padding(.horizontal, 14)
                            .padding(.vertical, 8)
                            .background(isSelected ? Theme.accent : Theme.cardElevated)
                            .foregroundStyle(isSelected ? .white : Theme.textSecondary)
                            .clipShape(Capsule())
                    }
                    .buttonStyle(.plain)
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
