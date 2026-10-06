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

    /// "just now" / "4s ago" / "2m ago" — freshness of a live data sample.
    static func secondsAgo(_ date: Date) -> String {
        let seconds = Int(Date.now.timeIntervalSince(date))
        if seconds < 2 { return "just now" }
        if seconds < 60 { return "\(seconds)s ago" }
        return "\(seconds / 60)m ago"
    }

    /// "2h 14m" / "42m" / "38s" / "now" — a forward countdown.
    ///
    /// Deliberately not `RelativeDateTimeFormatter`: that produces "in 42
    /// minutes", which is fine in a sentence and wrong in a badge that already
    /// says "Boards in". Seconds only appear inside the last minute, where
    /// they're the difference between hurrying and not.
    static func countdown(to date: Date, from now: Date = .now) -> String {
        let seconds = Int(date.timeIntervalSince(now).rounded())
        if seconds <= 0 { return "now" }
        if seconds < 60 { return "\(seconds)s" }
        let minutes = seconds / 60
        if minutes < 60 { return "\(minutes)m" }
        let hours = minutes / 60, remainder = minutes % 60
        return remainder > 0 ? "\(hours)h \(remainder)m" : "\(hours)h"
    }

    static func relative(_ date: Date) -> String {
        let f = RelativeDateTimeFormatter()
        f.unitsStyle = .abbreviated
        return f.localizedString(for: date, relativeTo: .now)
    }
}
