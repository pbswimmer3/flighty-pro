import Foundation

/// Time/date formatting helpers. Flight times are always rendered in the
/// *airport's* local timezone (like Flighty), not the phone's.
enum Fmt {

    static func time(_ date: Date, tz: TimeZone?) -> String {
        let f = DateFormatter()
        f.timeStyle = .short
        f.timeZone = tz ?? .current
        return f.string(from: date)
    }

    static func time(_ date: Date, airportIATA: String) -> String {
        time(date, tz: AirportDatabase.shared.airport(iata: airportIATA)?.timeZone)
    }

    static func dayAndDate(_ date: Date, tz: TimeZone? = nil) -> String {
        let f = DateFormatter()
        f.dateFormat = "EEE, MMM d"
        f.timeZone = tz ?? .current
        return f.string(from: date)
    }

    static func duration(_ interval: TimeInterval) -> String {
        let minutes = max(Int(interval / 60), 0)
        let h = minutes / 60, m = minutes % 60
        if h > 0 { return m > 0 ? "\(h)h \(m)m" : "\(h)h" }
        return "\(m)m"
    }

    static func delta(_ minutes: Int) -> String {
        if minutes == 0 { return "on time" }
        let h = abs(minutes) / 60, m = abs(minutes) % 60
        var span = h > 0 ? "\(h)h \(m)m" : "\(m)m"
        span = minutes > 0 ? "\(span) late" : "\(span) early"
        return span
    }

    static func relative(_ date: Date) -> String {
        let f = RelativeDateTimeFormatter()
        f.unitsStyle = .abbreviated
        return f.localizedString(for: date, relativeTo: .now)
    }
}
