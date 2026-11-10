import Foundation
import CoreLocation

/// What to print for a contact's route, after checking the schedule against
/// what the aircraft is visibly doing.
///
/// `FlightRouteService` keys on callsign and stores one route per flight
/// number, but airlines reuse a number for both legs of a rotation (SKW5351 is
/// SFO → SNA in the table and flies SNA → SFO too). Printed bare, the table
/// then labels an aircraft on short final into SFO as "SFO → SNA" — confidently
/// backwards. When the aircraft's own state contradicts the schedule, the
/// label says what it's doing ("Arriving SFO") and keeps the schedule as a
/// footnote; otherwise it's the schedule, marked as one.
struct RouteLabel: Equatable {
    /// "SFO → SNA", or "Arriving SFO" / "Departing SFO" when the schedule
    /// doesn't fit what the aircraft is doing.
    var headline: String
    /// "Scheduled" when the schedule fits; "Schedule says SFO → SNA" when it
    /// doesn't.
    var note: String
    var contradictsSchedule: Bool

    /// Thresholds for "this aircraft is clearly on the other leg". Generous on
    /// purpose: a wrong "Arriving" is worse than leaving the schedule up.
    enum Limits {
        static let nearAirportMiles = 46.0     // ~40 nm: inside the approach / departure phase
        static let terminalAltitudeFeet = 10_000
        static let lowLevelFeet = 4_000
        static let descendingFPM = -300
        static let climbingFPM = 300
        static let headingToleranceDegrees = 60.0
    }

    init(route: FlightRouteService.Route,
         report: TrafficReport,
         airport: (String) -> Airport? = { AirportDatabase.shared.airport(iata: $0) }) {
        let scheduled = route.arrow
        let fallback = (headline: scheduled, note: "Scheduled", contradicts: false)
        let reading = Self.contradiction(route: route, report: report, airport: airport) ?? fallback
        headline = reading.headline
        note = reading.note
        contradictsSchedule = reading.contradicts
    }

    private static func contradiction(route: FlightRouteService.Route,
                                      report: TrafficReport,
                                      airport: (String) -> Airport?)
        -> (headline: String, note: String, contradicts: Bool)? {
        // Only an airborne contact with a known heading says which way it's
        // going; a ground track or a heading-less record can't contradict.
        guard !report.onGround,
              let heading = report.headingDegrees,
              let altitude = report.altitudeFeet else { return nil }
        let here = report.coordinate
        let note = "Schedule says \(route.arrow)"

        // Coming *into* the scheduled origin: the reverse leg, arriving.
        if let origin = airport(route.origin.iata) {
            let field = CLLocationCoordinate2D(latitude: origin.lat, longitude: origin.lon)
            // Descending, or low and not climbing (a level segment on the
            // approach). Below 10,000 ft alone isn't enough: departures often
            // turn back over the field they just left.
            let rate = report.verticalRateFPM
            let descending = (rate.map { $0 <= Limits.descendingFPM } ?? false)
                || (altitude < Limits.lowLevelFeet && (rate ?? 0) < Limits.climbingFPM)
            if GreatCircle.distanceMiles(from: here, to: field) < Limits.nearAirportMiles,
               altitude < Limits.terminalAltitudeFeet,
               descending,
               offset(heading, GreatCircle.bearing(from: here, to: field)) <= Limits.headingToleranceDegrees {
                return ("Arriving \(route.origin.iata)", note, true)
            }
        }

        // Climbing *out of* the scheduled destination: the reverse leg, departing.
        if let destination = airport(route.destination.iata) {
            let field = CLLocationCoordinate2D(latitude: destination.lat, longitude: destination.lon)
            if GreatCircle.distanceMiles(from: here, to: field) < Limits.nearAirportMiles,
               altitude < Limits.terminalAltitudeFeet,
               (report.verticalRateFPM.map { $0 >= Limits.climbingFPM } ?? false),
               offset(heading, GreatCircle.bearing(from: field, to: here)) <= Limits.headingToleranceDegrees {
                return ("Departing \(route.destination.iata)", note, true)
            }
        }
        return nil
    }

    /// Smallest angle between two headings, 0…180.
    private static func offset(_ a: Double, _ b: Double) -> Double {
        abs(DeadReckoning.shortestAngleDelta(from: a, to: b))
    }
}
