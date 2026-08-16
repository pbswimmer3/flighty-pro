import Foundation
import CoreLocation

/// Neighbouring-traffic feed: every aircraft adsb.lol can see within a radius,
/// airborne and on the ground.
///
/// Coverage is volunteer-fed, so an empty result means "no receiver sees
/// anything here", not "no aircraft". Callers must say so rather than implying
/// an empty sky.
actor TrafficService {
    static let shared = TrafficService()

    enum TrafficError: LocalizedError {
        case badURL
        case http(Int)
        case transport(String)

        var errorDescription: String? {
            switch self {
            case .badURL: return "Bad request"
            case .http(let code): return code == 429
                ? "Rate limited by adsb.lol — backing off"
                : "adsb.lol returned HTTP \(code)"
            case .transport(let message): return message
            }
        }
    }

    /// All aircraft within `radiusNM` of a point. adsb.lol caps the radius at
    /// 250 nm; we clamp rather than let the server reject the call.
    func traffic(near center: CLLocationCoordinate2D, radiusNM: Int) async throws -> [TrafficReport] {
        let radius = min(max(radiusNM, 1), 250)
        let path = String(format: "https://api.adsb.lol/v2/lat/%.5f/lon/%.5f/dist/%d",
                          center.latitude, center.longitude, radius)
        guard let url = URL(string: path) else { throw TrafficError.badURL }

        do {
            let (data, response) = try await URLSession.shared.data(for: AdsbEndpoint.request(url))
            if let http = response as? HTTPURLResponse, !(200...299).contains(http.statusCode) {
                throw TrafficError.http(http.statusCode)
            }
            let received = Date.now
            let decoded = try JSONDecoder().decode(AdsbResponse.self, from: data)
            return decoded.aircraft.compactMap { $0.report(receivedAt: received) }
        } catch let error as TrafficError {
            throw error
        } catch is DecodingError {
            throw TrafficError.transport("Unexpected response from adsb.lol")
        } catch {
            throw TrafficError.transport(error.localizedDescription)
        }
    }
}
