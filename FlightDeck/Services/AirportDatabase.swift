import Foundation

/// Loads the bundled offline airport database (Resources/airports.json).
/// Kept as a plain singleton — the data is static, small (~100 airports),
/// and needed synchronously all over the UI.
final class AirportDatabase {
    static let shared = AirportDatabase()

    let airports: [Airport]
    private let byIATA: [String: Airport]

    private init() {
        var loaded: [Airport] = []
        if let url = Bundle.main.url(forResource: "airports", withExtension: "json"),
           let data = try? Data(contentsOf: url),
           let decoded = try? JSONDecoder().decode([Airport].self, from: data) {
            loaded = decoded
        }
        airports = loaded.sorted { $0.iata < $1.iata }
        byIATA = Dictionary(uniqueKeysWithValues: airports.map { ($0.iata, $0) })
    }

    func airport(iata: String) -> Airport? {
        byIATA[iata.uppercased()]
    }

    func search(_ query: String) -> [Airport] {
        let q = query.trimmingCharacters(in: .whitespaces)
        guard !q.isEmpty else { return airports }
        let upper = q.uppercased()
        return airports.filter {
            $0.iata.hasPrefix(upper)
                || $0.icao.hasPrefix(upper)
                || $0.name.localizedCaseInsensitiveContains(q)
                || $0.city.localizedCaseInsensitiveContains(q)
        }.sorted {
            // Exact IATA hits first.
            ($0.iata == upper ? 0 : 1, $0.iata) < ($1.iata == upper ? 0 : 1, $1.iata)
        }
    }
}
