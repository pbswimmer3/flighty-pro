import Foundation
import CoreLocation

/// Live aircraft position over ADS-B via the free, keyless adsb.lol API.
/// Given a flight's callsign (e.g. "DAL482") returns its current position —
/// used to draw the plane on the flight-detail map when tracking real flights.
actor AdsbService {
    static let shared = AdsbService()

    struct Position {
        var coordinate: CLLocationCoordinate2D
        var altitudeFeet: Int?       // nil while on the ground
        var groundSpeedKts: Int?
        var trackDegrees: Double?
    }

    func position(callSign: String) async -> Position? {
        let cs = callSign.trimmingCharacters(in: .whitespaces).uppercased()
        guard !cs.isEmpty,
              let url = URL(string: "https://api.adsb.lol/v2/callsign/\(cs)") else { return nil }
        do {
            let (data, _) = try await URLSession.shared.data(from: url)
            let decoded = try JSONDecoder().decode(Response.self, from: data)
            guard let ac = decoded.ac?.first, let lat = ac.lat, let lon = ac.lon else {
                return nil
            }
            var altitude: Int?
            if let alt = ac.alt_baro, case .number(let feet) = alt { altitude = Int(feet) }
            return Position(
                coordinate: CLLocationCoordinate2D(latitude: lat, longitude: lon),
                altitudeFeet: altitude,
                groundSpeedKts: ac.gs.map { Int($0) },
                trackDegrees: ac.track)
        } catch {
            return nil
        }
    }

    private struct Response: Decodable {
        var ac: [Aircraft]?
        struct Aircraft: Decodable {
            var lat: Double?
            var lon: Double?
            var alt_baro: FlexibleValue?  // number, or the string "ground"
            var gs: Double?
            var track: Double?
        }
    }
}
