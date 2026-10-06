import Foundation

/// Lifecycle phase of a tracked flight.
enum FlightPhase: String, Codable, CaseIterable {
    case scheduled
    case boarding
    case enRoute
    case landed
    case arrived      // landed + at gate
    case cancelled
    case diverted

    var label: String {
        switch self {
        case .scheduled: return "Scheduled"
        case .boarding: return "Boarding"
        case .enRoute: return "En Route"
        case .landed: return "Landed"
        case .arrived: return "Arrived"
        case .cancelled: return "Cancelled"
        case .diverted: return "Diverted"
        }
    }

    var isAirborne: Bool { self == .enRoute }
    var isComplete: Bool { self == .landed || self == .arrived }
}

/// Basic info about the aircraft flying the inbound leg — powers the
/// "Where's my plane" feature.
struct InboundFlight: Codable, Hashable {
    var flightNumber: String        // e.g. "DL 1187"
    var originIATA: String          // where the aircraft is coming from
    var scheduledArrival: Date      // when it should arrive at *our* origin
    var estimatedArrival: Date?
    var isDelayed: Bool { delayMinutes > 10 }
    var delayMinutes: Int {
        guard let est = estimatedArrival else { return 0 }
        return Int(est.timeIntervalSince(scheduledArrival) / 60)
    }
}

/// A tracked flight. All times are absolute `Date`s (UTC under the hood);
/// views format them in the airport's local timezone.
struct Flight: Identifiable, Codable, Hashable {
    var id: UUID = UUID()

    // Identity
    var airlineName: String         // "Delta Air Lines"
    var airlineCode: String         // "DL"
    var flightNumber: String        // "482"
    var callSign: String?           // "DAL482" — used for ADS-B position lookup

    // Route (IATA codes; resolved against AirportDatabase)
    var originIATA: String
    var destinationIATA: String

    // Times
    var scheduledDeparture: Date
    var estimatedDeparture: Date?
    var actualDeparture: Date?
    var scheduledArrival: Date
    var estimatedArrival: Date?
    var actualArrival: Date?

    // Ground details
    var departureTerminal: String?
    var departureGate: String?
    var arrivalTerminal: String?
    var arrivalGate: String?
    var baggageClaim: String?

    // Aircraft
    var aircraftModel: String?      // "Airbus A321neo"
    var registration: String?       // "N301DN"

    /// Where the user sat. Optional and user-entered — no provider supplies it,
    /// but the Passport's "top seat" stat is worth the one text field.
    var seat: String?

    var phase: FlightPhase = .scheduled
    var inbound: InboundFlight?

    /// Set when fetched from a live provider so we know refresh is possible.
    var isLiveData: Bool = false
    var lastUpdated: Date = .now

    // MARK: - Derived

    var displayNumber: String { "\(airlineCode) \(flightNumber)" }

    /// Best-known departure/arrival (actual > estimated > scheduled).
    var bestDeparture: Date { actualDeparture ?? estimatedDeparture ?? scheduledDeparture }
    var bestArrival: Date { actualArrival ?? estimatedArrival ?? scheduledArrival }

    var departureDelayMinutes: Int {
        Int(bestDeparture.timeIntervalSince(scheduledDeparture) / 60)
    }
    var arrivalDelayMinutes: Int {
        Int(bestArrival.timeIntervalSince(scheduledArrival) / 60)
    }

    var isDelayed: Bool {
        phase != .cancelled && (departureDelayMinutes > 10 || arrivalDelayMinutes > 10)
    }

    var duration: TimeInterval { bestArrival.timeIntervalSince(bestDeparture) }

    /// 0…1 progress along the flight based on the current clock.
    var progress: Double { progress(at: .now) }

    /// Progress at an arbitrary instant — lets a display-linked clock advance
    /// the plane smoothly instead of only on refresh.
    func progress(at date: Date) -> Double {
        if phase.isComplete { return 1 }
        if phase == .cancelled { return 0 }
        let start = bestDeparture, end = bestArrival
        guard end > start else { return 0 }
        let p = date.timeIntervalSince(start) / end.timeIntervalSince(start)
        return min(max(p, 0), 1)
    }

    /// Phase inferred from the clock — lets demo flights stay "live" and
    /// gives sensible fallbacks when a provider omits status.
    ///
    /// Collapsed out of `stage(at:)` rather than computed separately, so the
    /// coarse phase and the fine-grained stage on screen can never disagree
    /// about whether the flight has left. See `FlightStage`.
    var effectivePhase: FlightPhase { stage().phase }

    /// True while the flight is worth auto-refreshing / showing live.
    var isActive: Bool {
        let now = Date.now
        return now > scheduledDeparture.addingTimeInterval(-6 * 3600)
            && now < bestArrival.addingTimeInterval(2 * 3600)
            && phase != .cancelled
    }

    /// Sort key: active first, then by departure.
    var sortDate: Date { scheduledDeparture }

    // MARK: - Archival

    /// A flight stays in the live list for half an hour after it lands — long
    /// enough to still be the thing on screen at baggage claim, short enough
    /// that the next trip is what greets you when you reopen the app.
    static let archiveDelay: TimeInterval = 30 * 60

    /// The instant this flight moves itself into Past Flights.
    var archivesAt: Date {
        // A cancelled flight never lands, so hang it off the schedule instead.
        phase == .cancelled
            ? scheduledArrival.addingTimeInterval(Self.archiveDelay)
            : bestArrival.addingTimeInterval(Self.archiveDelay)
    }

    func isArchived(at date: Date = .now) -> Bool { date >= archivesAt }

    /// Counted by the Passport: a flight that actually happened. Cancellations
    /// are tracked separately — they're a delay statistic, not a trip.
    func hasFlown(at date: Date = .now) -> Bool {
        guard phase != .cancelled else { return false }
        if phase == .diverted { return date >= bestArrival }
        return date >= bestArrival
    }

    // MARK: - Passport inputs

    var originAirport: Airport? { AirportDatabase.shared.airport(iata: originIATA) }
    var destinationAirport: Airport? { AirportDatabase.shared.airport(iata: destinationIATA) }

    /// Great-circle route length. `nil` when either endpoint is missing from the
    /// bundled airport database — the Passport reports that gap rather than
    /// quietly undercounting the user's mileage.
    var routeDistanceMiles: Double? {
        guard let origin = originAirport, let destination = destinationAirport else { return nil }
        return GreatCircle.distanceMiles(from: origin.coordinate, to: destination.coordinate)
    }

    /// Aircraft type with the blanks trimmed off, or `nil` if we never learned it.
    var aircraftType: String? {
        guard let trimmed = aircraftModel?.trimmingCharacters(in: .whitespacesAndNewlines),
              !trimmed.isEmpty else { return nil }
        return trimmed
    }

    var tailNumber: String? {
        guard let trimmed = registration?.trimmingCharacters(in: .whitespacesAndNewlines),
              !trimmed.isEmpty else { return nil }
        return trimmed.uppercased()
    }

    /// US DOT counts an arrival as delayed at 15 minutes, not 10 — the Passport
    /// and the arrival forecast both use that definition so the numbers here
    /// mean the same thing as published on-time statistics.
    static let delayThresholdMinutes = 15

    var isDelayedByDOT: Bool {
        phase != .cancelled && arrivalDelayMinutes >= Self.delayThresholdMinutes
    }

    /// Calendar in the departure airport's timezone — a red-eye out of SFO
    /// belongs to the day it left California on, not the day it was in UTC.
    var originCalendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = originAirport?.timeZone ?? .current
        return calendar
    }

    var departureYear: Int { originCalendar.component(.year, from: scheduledDeparture) }
    var departureWeekday: Int { originCalendar.component(.weekday, from: scheduledDeparture) }
    var departureHourLocal: Int { originCalendar.component(.hour, from: scheduledDeparture) }

    var isInternational: Bool {
        guard let origin = originAirport, let destination = destinationAirport else { return false }
        return origin.country != destination.country
    }

    /// Six hours in the air is the usual long-haul cutoff.
    var isLongHaul: Bool { duration >= 6 * 3600 }

    /// Departs late evening or overnight and is long enough to sleep on.
    var isRedEye: Bool {
        let hour = departureHourLocal
        return (hour >= 21 || hour < 5) && duration >= 3 * 3600
    }
}
