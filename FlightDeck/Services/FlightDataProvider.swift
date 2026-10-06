import Foundation

enum FlightDataError: LocalizedError {
    case notFound
    case missingAPIKey
    case network(String)
    /// The body came back in a shape we couldn't read. Carries a short excerpt
    /// so the screen can say *what* arrived instead of shrugging — the old
    /// "unexpected response" told nobody anything, least of all whether the
    /// problem was the date, the plan, or the flight number.
    case decoding(String?)
    /// The service answered, and its answer was an error message. Shown as-is:
    /// "date is out of range for your subscription" is far more useful than
    /// anything this app could infer.
    case service(String)
    /// The requested date is beyond what live schedule feeds publish.
    case dateOutOfRange

    var errorDescription: String? {
        switch self {
        case .notFound:
            return "No flight found for that number and date."
        case .missingAPIKey:
            return "Live lookups need an AeroDataBox API key. Add one in Settings, or use Demo Mode."
        case .network(let msg):
            return "Network error: \(msg)"
        case .decoding(let excerpt):
            guard let excerpt, !excerpt.isEmpty else {
                return "The flight data service returned an empty response."
            }
            return "Couldn't read the flight data service's reply: \(excerpt)"
        case .service(let message):
            return message
        case .dateOutOfRange:
            return "Live schedules don't reach that date. AeroDataBox's Basic plan covers about a week either side of today."
        }
    }

    /// Whether offering "add it manually" is the useful next step. A missing
    /// key or a dropped connection is worth fixing instead.
    var isWorthAddingManually: Bool {
        switch self {
        case .notFound, .decoding, .service, .dateOutOfRange: return true
        case .missingAPIKey, .network: return false
        }
    }
}

/// Abstraction over "where flight schedules/status come from" so the app can
/// swap between Demo Mode and a real API without any UI changes.
protocol FlightDataProvider {
    /// Look up flights by designator (e.g. "DL 482" or "UA1")
    /// on a given calendar date (interpreted in the departure airport's zone
    /// by the backing service).
    func searchFlights(number: String, date: Date) async throws -> [Flight]

    /// Refresh a previously fetched flight. Returns an updated copy.
    func refresh(flight: Flight) async throws -> Flight
}
