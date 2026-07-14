import Foundation
import CoreLocation

/// Great-circle math for drawing realistic curved route lines on the map and
/// estimating the plane's position along the route.
enum GreatCircle {

    /// Interpolated points along the great circle between two coordinates.
    static func points(from a: CLLocationCoordinate2D,
                       to b: CLLocationCoordinate2D,
                       count: Int = 64) -> [CLLocationCoordinate2D] {
        guard count > 1 else { return [a, b] }

        let lat1 = a.latitude * .pi / 180, lon1 = a.longitude * .pi / 180
        let lat2 = b.latitude * .pi / 180, lon2 = b.longitude * .pi / 180

        // Angular distance (haversine).
        let d = 2 * asin(sqrt(pow(sin((lat2 - lat1) / 2), 2)
                              + cos(lat1) * cos(lat2) * pow(sin((lon2 - lon1) / 2), 2)))
        guard d > 1e-8 else { return [a, b] }

        var result: [CLLocationCoordinate2D] = []
        for i in 0...count {
            let f = Double(i) / Double(count)
            let A = sin((1 - f) * d) / sin(d)
            let B = sin(f * d) / sin(d)
            let x = A * cos(lat1) * cos(lon1) + B * cos(lat2) * cos(lon2)
            let y = A * cos(lat1) * sin(lon1) + B * cos(lat2) * sin(lon2)
            let z = A * sin(lat1) + B * sin(lat2)
            let lat = atan2(z, sqrt(x * x + y * y))
            let lon = atan2(y, x)
            result.append(CLLocationCoordinate2D(latitude: lat * 180 / .pi,
                                                 longitude: lon * 180 / .pi))
        }
        return result
    }

    /// Point at `fraction` (0…1) along the great circle — used to place the
    /// plane icon when we don't have a live ADS-B position.
    static func intermediatePoint(from a: CLLocationCoordinate2D,
                                  to b: CLLocationCoordinate2D,
                                  fraction: Double) -> CLLocationCoordinate2D {
        let pts = points(from: a, to: b, count: 100)
        let idx = min(max(Int((fraction * 100).rounded()), 0), pts.count - 1)
        return pts[idx]
    }

    /// Distance in statute miles.
    static func distanceMiles(from a: CLLocationCoordinate2D, to b: CLLocationCoordinate2D) -> Double {
        let locA = CLLocation(latitude: a.latitude, longitude: a.longitude)
        let locB = CLLocation(latitude: b.latitude, longitude: b.longitude)
        return locA.distance(from: locB) / 1609.344
    }

    /// Initial bearing in degrees from a to b — rotates the plane icon.
    static func bearing(from a: CLLocationCoordinate2D, to b: CLLocationCoordinate2D) -> Double {
        let lat1 = a.latitude * .pi / 180, lat2 = b.latitude * .pi / 180
        let dLon = (b.longitude - a.longitude) * .pi / 180
        let y = sin(dLon) * cos(lat2)
        let x = cos(lat1) * sin(lat2) - sin(lat1) * cos(lat2) * cos(dLon)
        let deg = atan2(y, x) * 180 / .pi
        return (deg + 360).truncatingRemainder(dividingBy: 360)
    }
}
