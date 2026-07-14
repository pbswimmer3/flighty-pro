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
    var progress: Double {
        if phase.isComplete { return 1 }
        if phase == .cancelled { return 0 }
        let start = bestDeparture, end = bestArrival
        guard end > start else { return 0 }
        let p = Date.now.timeIntervalSince(start) / end.timeIntervalSince(start)
        return min(max(p, 0), 1)
    }

    /// Phase inferred from the clock — lets demo flights stay "live" and
    /// gives sensible fallbacks when a provider omits status.
    var effectivePhase: FlightPhase {
        switch phase {
        case .cancelled, .diverted, .landed, .arrived:
            return phase
        default:
            let now = Date.now
            if now >= bestArrival, now >= bestDeparture { return .arrived }
            if now >= bestDeparture { return .enRoute }
            if now >= bestDeparture.addingTimeInterval(-40 * 60) { return .boarding }
            return .scheduled
        }
    }

    /// True while the flight is worth auto-refreshing / showing live.
    var isActive: Bool {
        let now = Date.now
        return now > scheduledDeparture.addingTimeInterval(-6 * 3600)
            && now < bestArrival.addingTimeInterval(2 * 3600)
            && phase != .cancelled
    }

    /// Sort key: active first, then by departure.
    var sortDate: Date { scheduledDeparture }
}
