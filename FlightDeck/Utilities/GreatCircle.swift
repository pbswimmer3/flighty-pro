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
    ///
    /// Computed directly rather than by sampling a 100-point polyline: that
    /// quantised the position to 1% of the route, which on a five-hour flight
    /// is a visible jump every three minutes.
    static func intermediatePoint(from a: CLLocationCoordinate2D,
                                  to b: CLLocationCoordinate2D,
                                  fraction: Double) -> CLLocationCoordinate2D {
        let f = min(max(fraction, 0), 1)

        let lat1 = a.latitude * .pi / 180, lon1 = a.longitude * .pi / 180
        let lat2 = b.latitude * .pi / 180, lon2 = b.longitude * .pi / 180

        let d = 2 * asin(sqrt(pow(sin((lat2 - lat1) / 2), 2)
                              + cos(lat1) * cos(lat2) * pow(sin((lon2 - lon1) / 2), 2)))
        guard d > 1e-8 else { return a }

        let A = sin((1 - f) * d) / sin(d)
        let B = sin(f * d) / sin(d)
        let x = A * cos(lat1) * cos(lon1) + B * cos(lat2) * cos(lon2)
        let y = A * cos(lat1) * sin(lon1) + B * cos(lat2) * sin(lon2)
        let z = A * sin(lat1) + B * sin(lat2)

        return CLLocationCoordinate2D(latitude: atan2(z, sqrt(x * x + y * y)) * 180 / .pi,
                                      longitude: atan2(y, x) * 180 / .pi)
    }

    /// Distance in statute miles.
    static func distanceMiles(from a: CLLocationCoordinate2D, to b: CLLocationCoordinate2D) -> Double {
        let locA = CLLocation(latitude: a.latitude, longitude: a.longitude)
        let locB = CLLocation(latitude: b.latitude, longitude: b.longitude)
        return locA.distance(from: locB) / 1609.344
    }

    /// The point reached by travelling `distanceMetres` from `origin` along
    /// `bearingDegrees` — the propagation step behind dead reckoning.
    static func destination(from origin: CLLocationCoordinate2D,
                            bearingDegrees: Double,
                            distanceMetres: Double) -> CLLocationCoordinate2D {
        let theta = bearingDegrees * .pi / 180
        let lat1 = origin.latitude * .pi / 180
        let lon1 = origin.longitude * .pi / 180

        // Spherical propagation with a mean Earth radius carries a systematic
        // error of up to ~0.3% — around 20 m over a full extrapolation window
        // at cruise, which is the same order as the ADS-B accuracy we're
        // claiming. Using the WGS-84 radius of curvature in the direction of
        // travel brings it under a metre, and matches how MapKit and
        // CLLocation measure.
        let angular = distanceMetres / wgs84RadiusOfCurvature(latitude: lat1, azimuth: theta)

        let sinLat2 = sin(lat1) * cos(angular) + cos(lat1) * sin(angular) * cos(theta)
        let lat2 = asin(min(max(sinLat2, -1), 1))
        let lon2 = lon1 + atan2(sin(theta) * sin(angular) * cos(lat1),
                                cos(angular) - sin(lat1) * sinLat2)

        return CLLocationCoordinate2D(latitude: lat2 * 180 / .pi,
                                      longitude: normalisedLongitude(lon2 * 180 / .pi))
    }

    /// Euler's radius-of-curvature formula on the WGS-84 ellipsoid: blends the
    /// meridional radius (relevant heading north) and the prime-vertical radius
    /// (relevant heading east) by the azimuth of travel. Both angles are in
    /// radians.
    private static func wgs84RadiusOfCurvature(latitude: Double, azimuth: Double) -> Double {
        let a = 6_378_137.0                  // semi-major axis
        let eSquared = 0.006_694_379_990_14  // first eccentricity squared
        let w = 1 - eSquared * pow(sin(latitude), 2)
        let primeVertical = a / sqrt(w)
        let meridional = a * (1 - eSquared) / pow(w, 1.5)
        return 1 / (pow(cos(azimuth), 2) / meridional + pow(sin(azimuth), 2) / primeVertical)
    }

    /// Wraps a longitude into −180…180 so propagation across the antimeridian
    /// doesn't produce coordinates MapKit refuses to plot.
    static func normalisedLongitude(_ degrees: Double) -> Double {
        var d = degrees.truncatingRemainder(dividingBy: 360)
        if d > 180 { d -= 360 }
        if d < -180 { d += 360 }
        return d
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
