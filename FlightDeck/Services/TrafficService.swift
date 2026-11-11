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

    /// All aircraft within `radiusNM` of a point. adsb.lol caps the radius at
    /// 250 nm; we clamp rather than let the server reject the call.
    ///
    /// Goes through `AdsbClient`, so it may wait for a slot in the shared
    /// request budget, and it throws `AdsbClient.Failure` — `.rateLimited`
    /// above all, which callers must sleep through rather than retry.
    func traffic(near center: CLLocationCoordinate2D, radiusNM: Int) async throws -> [TrafficReport] {
        let radius = min(max(radiusNM, 1), 250)
        let path = String(format: "https://api.adsb.lol/v2/lat/%.5f/lon/%.5f/dist/%d",
                          center.latitude, center.longitude, radius)
        guard let url = URL(string: path) else { throw AdsbClient.Failure.badRequest }

        let data = try await AdsbClient.shared.data(from: url)
        let received = Date.now
        do {
            let decoded = try JSONDecoder().decode(AdsbResponse.self, from: data)
            return decoded.aircraft.compactMap { $0.report(receivedAt: received) }
        } catch {
            throw AdsbClient.Failure.badResponse
        }
    }
}
