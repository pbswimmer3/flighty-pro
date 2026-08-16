import Foundation
import CoreLocation

/// Everything needed to say where an aircraft is *now* given where it was
/// when it last transmitted.
struct KinematicState {
    var coordinate: CLLocationCoordinate2D
    var headingDegrees: Double
    var groundSpeedKts: Double
    /// When this state was true — `receivedAt - seen_pos`, not receipt time.
    var validAt: Date

    init(coordinate: CLLocationCoordinate2D,
         headingDegrees: Double,
         groundSpeedKts: Double,
         validAt: Date) {
        self.coordinate = coordinate
        self.headingDegrees = headingDegrees
        self.groundSpeedKts = groundSpeedKts
        self.validAt = validAt
    }

    init(_ report: TrafficReport) {
        self.init(coordinate: report.coordinate,
                  headingDegrees: report.headingDegrees ?? 0,
                  groundSpeedKts: report.groundSpeedKts ?? 0,
                  validAt: report.validAt)
    }
}

/// Client-side dead reckoning — the reason the map looks smooth.
///
/// The feed is discrete and irregular (fix ages in a single response range from
/// a fraction of a second to tens of seconds), so binding annotations straight
/// to received positions produces uneven jumping. Instead we hold a kinematic
/// state per aircraft, integrate it forward every display frame, and ease onto
/// each new measurement rather than snapping to it.
///
/// What's drawn is therefore an **estimate, not a report**, which is why
/// extrapolation is capped and stale targets are marked rather than trusted.
enum DeadReckoning {

    enum Limits {
        /// Beyond this the projection is more invention than measurement:
        /// mark the target stale and stop moving it.
        static let staleAfter: TimeInterval = 30
        /// Beyond this, drop it entirely.
        static let dropAfter: TimeInterval = 60
        /// How long to ease from the extrapolated position onto a new fix.
        /// Long enough to read as motion, short enough to stay honest.
        static let reconcileDuration: TimeInterval = 0.6
        /// Below this an aircraft is parked; integrating its "speed" just
        /// accumulates floating-point drift and makes gates creep.
        static let stationaryKts: Double = 1.0
    }

    /// Integrate a state forward to `time`.
    static func project(_ state: KinematicState, to time: Date) -> CLLocationCoordinate2D {
        let elapsed = time.timeIntervalSince(state.validAt)
        guard elapsed > 0 else { return state.coordinate }
        guard state.groundSpeedKts >= Limits.stationaryKts else { return state.coordinate }

        // Freeze at the staleness cap instead of drifting silently: a 49 s old
        // fix at cruise speed would otherwise be placed ~7 nm from reality.
        let dt = min(elapsed, Limits.staleAfter)
        let metresPerSecond = state.groundSpeedKts * 0.514444
        return GreatCircle.destination(from: state.coordinate,
                                       bearingDegrees: state.headingDegrees,
                                       distanceMetres: metresPerSecond * dt)
    }

    /// Blend from the currently-rendered state toward a new measurement.
    /// `progress` is 0…1 through `reconcileDuration`.
    static func reconcile(current: KinematicState,
                          toward measured: KinematicState,
                          progress: Double) -> KinematicState {
        let p = ease(clamp01(progress))
        return KinematicState(
            coordinate: interpolate(current.coordinate, measured.coordinate, p),
            headingDegrees: blendAngle(from: current.headingDegrees,
                                       to: measured.headingDegrees,
                                       progress: p),
            groundSpeedKts: current.groundSpeedKts
                + (measured.groundSpeedKts - current.groundSpeedKts) * p,
            validAt: measured.validAt)
    }

    // MARK: - Math helpers

    /// Signed shortest angular distance, −180…180. Without this a 359° → 1°
    /// turn animates 358° the wrong way.
    static func shortestAngleDelta(from: Double, to: Double) -> Double {
        var delta = (to - from).truncatingRemainder(dividingBy: 360)
        if delta > 180 { delta -= 360 }
        if delta < -180 { delta += 360 }
        return delta
    }

    static func blendAngle(from: Double, to: Double, progress: Double) -> Double {
        let blended = from + shortestAngleDelta(from: from, to: to) * clamp01(progress)
        return (blended.truncatingRemainder(dividingBy: 360) + 360)
            .truncatingRemainder(dividingBy: 360)
    }

    /// Linear blend between two coordinates, taking the short way around the
    /// antimeridian. Reconciliation distances are metres, so the flat
    /// approximation costs nothing here.
    static func interpolate(_ a: CLLocationCoordinate2D,
                            _ b: CLLocationCoordinate2D,
                            _ progress: Double) -> CLLocationCoordinate2D {
        let p = clamp01(progress)
        let lonDelta = shortestAngleDelta(from: a.longitude, to: b.longitude)
        return CLLocationCoordinate2D(
            latitude: a.latitude + (b.latitude - a.latitude) * p,
            longitude: GreatCircle.normalisedLongitude(a.longitude + lonDelta * p))
    }

    /// Smoothstep — an ease-out landing reads as the target settling into
    /// place, where a linear blend still shows a corner at each end.
    static func ease(_ p: Double) -> Double {
        let x = clamp01(p)
        return x * x * (3 - 2 * x)
    }

    static func clamp01(_ value: Double) -> Double { min(max(value, 0), 1) }
}
