import Foundation

/// The one door to api.adsb.lol. Every request from every screen goes through
/// here, so the app spends one budget instead of each poller spending its own.
///
/// adsb.lol is free and keyless, but not unlimited. Its API notes say limits
/// are "dynamic based on the environment load", and since November 2026 every
/// response carries `x-ratelimit-limit: 500, 500;w=86400`: 500 requests per
/// client address per UTC day, with `/v2/callsign` and `/v2/lat/…/dist`
/// drawing down the same `x-ratelimit-remaining`, and `x-ratelimit-reset`
/// counting down to 00:00 UTC.
///
/// Before this existed the tracking map polled two endpoints every five
/// seconds — 24 requests a minute, a day's quota in about twenty minutes — the
/// flight page kept polling from a background tab, and a 429 changed nothing:
/// the banner said "backing off" while both loops carried on at full rate
/// (TestFlight #12, #14).
///
/// Three rules:
/// 1. **A 429 stops everything.** Nothing is sent until `Retry-After`, or a
///    doubling backoff from 30 s when the server doesn't say. Callers get
///    `.rateLimited(until:)` at once, without a round trip.
/// 2. **Requests are spaced.** Never closer than `minimumSpacing`, and while
///    the server reports its quota, no faster than would spend what's left
///    within `budgetHorizon` — a long session slows down gently instead of
///    running dry halfway through a flight.
/// 3. **Short bursts are allowed** (`burst`), so opening a screen doesn't sit
///    out the gap left by another screen's last request.
actor AdsbClient {
    static let shared = AdsbClient()

    enum Failure: LocalizedError {
        case rateLimited(until: Date)
        case http(Int)
        case transport(String)
        case badRequest
        case badResponse

        var errorDescription: String? {
            switch self {
            case .rateLimited(let until):
                return "Rate limited by adsb.lol — retrying at "
                    + until.formatted(date: .omitted, time: .shortened)
            case .http(let code): return "adsb.lol returned HTTP \(code)"
            case .transport(let message): return message
            case .badRequest: return "Bad request"
            case .badResponse: return "Unexpected response from adsb.lol"
            }
        }
    }

    enum Pacing {
        /// Never closer than this, whatever the quota allows. Motion comes
        /// from dead reckoning, not the sample rate, so polling faster buys
        /// nothing on screen.
        static let minimumSpacing: TimeInterval = 10
        /// Spend what's left no faster than would use it all up in this long.
        /// Re-read from every response, so it decays rather than runs out:
        /// a full 500 allows one request every ~14 s; two hours of
        /// continuous tracking later about 180 are left, at one every ~40 s.
        static let budgetHorizon: TimeInterval = 2 * 60 * 60
        /// Requests that may go out back to back after a quiet spell.
        static let burst = 3
        /// First wait after a 429 that carries no `Retry-After`; doubles.
        static let firstBackoff: TimeInterval = 30
        /// Longest the app will sit out. The quota is per address, and
        /// landing swaps in-flight Wi-Fi for cellular — a new address with a
        /// fresh quota — so one probe every 15 minutes beats waiting for
        /// midnight UTC.
        static let longestWait: TimeInterval = 15 * 60
    }

    /// When the next request would be due if they went out exactly one
    /// spacing apart (GCRA's "theoretical arrival time").
    private var dueAt = Date.distantPast
    private var blockedUntil: Date?
    private var rateLimitStreak = 0
    private var remaining: Int?
    private var resetAt: Date?

    /// GETs `url`, waiting for a slot in the shared budget first. Throws
    /// `Failure` for anything but a 2xx — immediately, with no request, while
    /// a rate limit is in force.
    func data(from url: URL) async throws -> Data {
        let now = Date.now
        if let blockedUntil, blockedUntil > now { throw Failure.rateLimited(until: blockedUntil) }

        // Reserve the slot *before* suspending: the actor is re-entrant, and
        // two pollers arriving together must not both claim the same gap.
        let spacing = currentSpacing(at: now)
        let due = max(dueAt, now)
        let sendAt = max(now, due.addingTimeInterval(-spacing * Double(Pacing.burst - 1)))
        dueAt = due.addingTimeInterval(spacing)
        let reservation = dueAt

        if sendAt > now {
            do {
                try await Task.sleep(nanoseconds: UInt64(sendAt.timeIntervalSince(now) * 1_000_000_000))
            } catch {
                // The screen went away while queued. Hand the slot back if
                // nobody has queued behind it.
                if dueAt == reservation { dueAt = due }
                throw error
            }
        }
        // Another request may have been turned away while this one waited.
        if let blockedUntil, blockedUntil > Date.now { throw Failure.rateLimited(until: blockedUntil) }

        let result: (Data, URLResponse)
        do {
            result = try await URLSession.shared.data(for: Self.request(url))
        } catch {
            throw Failure.transport(error.localizedDescription)
        }
        let (data, response) = result
        guard let http = response as? HTTPURLResponse else { return data }

        let received = Date.now
        readQuota(http, at: received)

        if http.statusCode == 429 {
            rateLimitStreak += 1
            let until = received.addingTimeInterval(rateLimitWait(http, at: received))
            blockedUntil = until
            throw Failure.rateLimited(until: until)
        }
        guard (200...299).contains(http.statusCode) else { throw Failure.http(http.statusCode) }

        rateLimitStreak = 0
        if remaining == 0, let resetAt {
            // That was the last request the quota allows; don't spend another
            // round trip to be told so by a 429.
            blockedUntil = min(resetAt, received.addingTimeInterval(Pacing.longestWait))
        }
        return data
    }

    // MARK: - Budget

    /// The gap the quota can afford right now. With no quota headers (or a
    /// window that has already reset) only the floor applies.
    private func currentSpacing(at now: Date) -> TimeInterval {
        guard let remaining, let resetAt, resetAt > now else { return Pacing.minimumSpacing }
        let window = min(resetAt.timeIntervalSince(now), Pacing.budgetHorizon)
        return max(Pacing.minimumSpacing, window / Double(max(remaining, 1)))
    }

    private func readQuota(_ http: HTTPURLResponse, at now: Date) {
        if let left = Self.leadingNumber(http.value(forHTTPHeaderField: "x-ratelimit-remaining")) {
            remaining = Int(left)
        }
        if let seconds = Self.leadingNumber(http.value(forHTTPHeaderField: "x-ratelimit-reset")) {
            resetAt = now.addingTimeInterval(seconds)
        }
    }

    /// How long to stay away after a 429: what the server asks for, else
    /// until the quota resets if it's spent, else a doubling backoff.
    private func rateLimitWait(_ http: HTTPURLResponse, at now: Date) -> TimeInterval {
        let retryAfter = http.value(forHTTPHeaderField: "Retry-After")
        let wait: TimeInterval
        if let seconds = Self.leadingNumber(retryAfter) {
            wait = seconds
        } else if let retryAfter, let date = Self.httpDate(retryAfter) {
            wait = date.timeIntervalSince(now)
        } else if remaining == 0, let resetAt {
            wait = resetAt.timeIntervalSince(now)
        } else {
            wait = Pacing.firstBackoff * pow(2, Double(min(max(rateLimitStreak - 1, 0), 10)))
        }
        return min(max(wait, Pacing.minimumSpacing), Pacing.longestWait)
    }

    // MARK: - Plumbing

    private static func request(_ url: URL) -> URLRequest {
        var request = URLRequest(url: url)
        // Positions go stale in seconds — a cached response is worse than none.
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.timeoutInterval = 12
        return request
    }

    /// The number a header starts with: "499", "58511", or the "500" in
    /// "500, 500;w=86400".
    private static func leadingNumber(_ value: String?) -> TimeInterval? {
        guard let value else { return nil }
        let number = value.trimmingCharacters(in: .whitespaces).prefix { $0.isASCII && ($0.isNumber || $0 == ".") }
        return TimeInterval(String(number))
    }

    /// `Retry-After` may also be an HTTP date.
    private static func httpDate(_ value: String) -> Date? {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "GMT")
        formatter.dateFormat = "EEE, dd MMM yyyy HH:mm:ss zzz"
        return formatter.date(from: value)
    }
}
