import Foundation

/// Airport Intelligence data source #2: live METARs from aviationweather.gov.
/// Keyless, JSON, worldwide coverage — works for non-US airports where the
/// FAA feed doesn't.
actor WeatherService {
    static let shared = WeatherService()

    private var cache: [String: (metar: Metar, fetched: Date)] = [:]
    private let cacheTTL: TimeInterval = 300

    /// Fetch a METAR by ICAO id (e.g. "KSFO", "EGLL").
    func metar(icao: String) async -> Metar? {
        let key = icao.uppercased()
        if let hit = cache[key], Date.now.timeIntervalSince(hit.fetched) < cacheTTL {
            return hit.metar
        }
        var components = URLComponents(string: "https://aviationweather.gov/api/data/metar")
        components?.queryItems = [
            URLQueryItem(name: "ids", value: key),
            URLQueryItem(name: "format", value: "json"),
        ]
        guard let url = components?.url else { return nil }
        do {
            let (data, _) = try await URLSession.shared.data(from: url)
            let metars = try JSONDecoder().decode([Metar].self, from: data)
            guard let first = metars.first else { return nil }
            cache[key] = (first, .now)
            return first
        } catch {
            return nil
        }
    }

    func metar(for airport: Airport) async -> Metar? {
        await metar(icao: airport.icao)
    }
}
