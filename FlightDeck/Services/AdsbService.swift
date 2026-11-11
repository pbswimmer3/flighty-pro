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
    ///
    /// Throws (`AdsbClient.Failure`) when the request itself failed. That used
    /// to come back as `nil` too, so a 429 read as "aircraft out of coverage"
    /// and the tracker polled straight through it.
    func report(callSign: String) async throws -> TrafficReport? {
        let cs = callSign.trimmingCharacters(in: .whitespaces).uppercased()
        guard !cs.isEmpty,
              let encoded = cs.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed),
              let url = URL(string: "https://api.adsb.lol/v2/callsign/\(encoded)") else { return nil }

        let data = try await AdsbClient.shared.data(from: url)
        let received = Date.now
        guard let decoded = try? JSONDecoder().decode(AdsbResponse.self, from: data) else {
            throw AdsbClient.Failure.badResponse
        }
        // Newest fix wins if the callsign somehow matches two airframes.
        return decoded.aircraft
            .compactMap { $0.report(receivedAt: received) }
            .min { $0.fixAge < $1.fixAge }
    }
}
