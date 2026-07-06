import Foundation

enum FlightDataError: LocalizedError {
    case notFound
    case missingAPIKey
    case network(String)
    case decoding

    var errorDescription: String? {
        switch self {
        case .notFound:
            return "No flight found for that number and date."
        case .missingAPIKey:
            return "Live lookups need an AeroDataBox API key. Add one in Settings, or use Demo Mode."
        case .network(let msg):
            return "Network error: \(msg)"
        case .decoding:
            return "The flight data service returned an unexpected response."
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
