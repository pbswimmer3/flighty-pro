import Foundation
import CoreLocation

/// Live aircraft position over ADS-B via the free, keyless adsb.lol API.
/// Given a flight's callsign (e.g. "DAL482") returns its current report —
/// used to drive the plane on the flight-detail map when tracking real flights.
actor AdsbService {
    static let shared = AdsbService()

    /// Returns the newest report for a callsign, or `nil` if the aircraft isn't
    /// in coverage. Heading comes back for surface aircraft too, which it did
    /// not before: airborne aircraft report `track`, aircraft on the ground
    /// report `true_heading`, and reading only the former made taxiing planes
    /// lose their rotation.
    func report(callSign: String) async -> TrafficReport? {
        let cs = callSign.trimmingCharacters(in: .whitespaces).uppercased()
        guard !cs.isEmpty,
              let encoded = cs.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed),
              let url = URL(string: "https://api.adsb.lol/v2/callsign/\(encoded)") else { return nil }
        do {
            let (data, _) = try await URLSession.shared.data(for: AdsbEndpoint.request(url))
            let decoded = try JSONDecoder().decode(AdsbResponse.self, from: data)
            // Newest fix wins if the callsign somehow matches two airframes.
            return decoded.aircraft
                .compactMap { $0.report() }
                .min { $0.fixAge < $1.fixAge }
        } catch {
            return nil
        }
    }
}

/// Shared request construction for the adsb.lol endpoints.
enum AdsbEndpoint {
    static func request(_ url: URL) -> URLRequest {
        var request = URLRequest(url: url)
        // Positions go stale in seconds — a cached response is worse than none.
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.timeoutInterval = 12
        return request
    }
}
