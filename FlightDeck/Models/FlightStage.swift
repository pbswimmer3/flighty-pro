import SwiftUI

/// Where a flight is in its day, at a resolution people actually think in.
///
/// `FlightPhase` is what a provider *tells* us (scheduled / boarding / en route
/// / arrived) and it updates only when someone refreshes. This is the finer
/// grain the app derives from the clock, so the screen moves through
/// "Boarding" → "Gate closing" → "Taxiing" → "In the air" → "Landing soon" →
/// "Taxiing to gate" → "At the gate" on its own, the way a flight actually
/// does — no polling required, and correct in Demo Mode too.
///
/// `FlightPhase` is deliberately left alone: it's persisted in `flights.json`
/// and read by the Passport and the forecaster, and none of them want thirteen
/// cases. `Flight.effectivePhase` is derived from this, so the two can't drift.
enum FlightStage: String, CaseIterable, Equatable {
    case scheduled          // more than a day out
    case checkInOpen        // check-in is open, boarding is not close
    case boardingSoon       // the "start heading to the gate" hour
    case boarding
    case gateClosing        // final call — doors go in minutes
    case taxiingOut
    case airborne
    case landingSoon
    case taxiingIn          // on the ground, not at a gate yet
    case atGate
    case arrived            // bags should be out; the flight is done
    case cancelled
    case diverted

    var label: String {
        switch self {
        case .scheduled:    return "Scheduled"
        case .checkInOpen:  return "Check-in open"
        case .boardingSoon: return "Boarding soon"
        case .boarding:     return "Boarding"
        case .gateClosing:  return "Gate closing"
        case .taxiingOut:   return "Taxiing"
        case .airborne:     return "In the air"
        case .landingSoon:  return "Landing soon"
        case .taxiingIn:    return "Taxiing to gate"
        case .atGate:       return "At the gate"
        case .arrived:      return "Arrived"
        case .cancelled:    return "Cancelled"
        case .diverted:     return "Diverted"
        }
    }

    var systemImage: String {
        switch self {
        case .scheduled:    return "calendar"
        case .checkInOpen:  return "checkmark.rectangle.portrait"
        case .boardingSoon: return "figure.walk"
        case .boarding:     return "person.2.fill"
        case .gateClosing:  return "door.left.hand.closed"
        case .taxiingOut:   return "airplane.departure"
        case .airborne:     return "airplane"
        case .landingSoon:  return "airplane.arrival"
        case .taxiingIn:    return "airplane.arrival"
        case .atGate:       return "door.left.hand.open"
        case .arrived:      return "checkmark.circle.fill"
        case .cancelled:    return "xmark.octagon.fill"
        case .diverted:     return "arrow.triangle.branch"
        }
    }

    var tint: Color {
        switch self {
        case .cancelled, .diverted:            return Theme.red
        case .gateClosing:                     return Theme.orange
        case .boarding:                        return Theme.green
        case .taxiingIn, .atGate, .arrived:    return Theme.green
        default:                               return Theme.accent
        }
    }

    /// Wheels-up to wheels-down. Taxiing counts as "under way" for the phase
    /// mapping but not as airborne.
    var isAirborne: Bool { self == .airborne || self == .landingSoon }

    /// The flight is down, whatever is still happening on the ground.
    var isOnGroundAtDestination: Bool {
        self == .taxiingIn || self == .atGate || self == .arrived
    }

    /// The doors are the thing to worry about right now.
    var isBoardingWindow: Bool {
        self == .boardingSoon || self == .boarding || self == .gateClosing
    }

    var phase: FlightPhase {
        switch self {
        case .cancelled:                            return .cancelled
        case .diverted:                             return .diverted
        case .scheduled, .checkInOpen, .boardingSoon: return .scheduled
        case .boarding, .gateClosing:               return .boarding
        case .taxiingOut, .airborne, .landingSoon:  return .enRoute
        case .taxiingIn:                            return .landed
        case .atGate, .arrived:                     return .arrived
        }
    }
}

// MARK: - Milestones

/// A dated point in a flight's day. One list drives the timeline on screen,
/// the countdown on the card, *and* the notifications — a second copy of these
/// times would be a second thing to get wrong.
struct FlightMilestone: Identifiable, Hashable {
    enum Kind: String, CaseIterable, Codable {
        case checkIn
        case boarding
        case gateClose
        case departure
        case landing
        case bags

        var label: String {
            switch self {
            case .checkIn:   return "Check-in opens"
            case .boarding:  return "Boarding"
            case .gateClose: return "Gate closes"
            case .departure: return "Departure"
            case .landing:   return "Arrival"
            case .bags:      return "Baggage"
            }
        }

        var systemImage: String {
            switch self {
            case .checkIn:   return "checkmark.rectangle.portrait"
            case .boarding:  return "person.2.fill"
            case .gateClose: return "door.left.hand.closed"
            case .departure: return "airplane.departure"
            case .landing:   return "airplane.arrival"
            case .bags:      return "suitcase.fill"
            }
        }
    }

    var kind: Kind
    var date: Date
    /// True when we worked the time out from the schedule rather than being
    /// told it. Everything except departure and arrival is estimated.
    var isEstimated: Bool

    var id: Kind { kind }
}

// MARK: - Flight timing

extension Flight {

    /// How long before departure boarding starts.
    ///
    /// Airlines don't publish this in any feed we can read, so it's derived:
    /// wide-body international boarding runs closer to 50 minutes, a domestic
    /// narrow-body closer to 35. Being ten minutes early to a gate costs
    /// nothing; being ten minutes late costs the flight, so the estimate leans
    /// early on purpose.
    var boardingLead: TimeInterval {
        (isInternational || isLongHaul) ? 50 * 60 : 35 * 60
    }

    /// Doors close before push-back, and this is the number most people
    /// actually need. 15 minutes is the common published figure; long-haul
    /// international is usually 20.
    var gateCloseLead: TimeInterval {
        (isInternational || isLongHaul) ? 20 * 60 : 15 * 60
    }

    /// Check-in opens a day out almost everywhere.
    static let checkInLead: TimeInterval = 24 * 3600

    /// The "start walking to the gate" window ahead of boarding.
    static let boardingSoonLead: TimeInterval = 60 * 60

    /// Gate-to-runway and runway-to-gate. Rough by nature; they only decide
    /// which word is on screen, never a time that gets displayed as fact.
    static let taxiOutAllowance: TimeInterval = 15 * 60
    static let taxiInAllowance: TimeInterval = 8 * 60

    /// When "landing soon" starts. Capped at a quarter of the flight so a
    /// 40-minute hop isn't described as landing before it has climbed.
    var landingSoonWindow: TimeInterval {
        min(30 * 60, max(duration * 0.25, 5 * 60))
    }

    /// Bags take longer off a wide-body, and longer again through customs.
    var bagsAllowance: TimeInterval {
        isInternational ? 35 * 60 : 20 * 60
    }

    // MARK: Derived instants

    var checkInOpensAt: Date { scheduledDeparture.addingTimeInterval(-Self.checkInLead) }
    var boardingStartsAt: Date { bestDeparture.addingTimeInterval(-boardingLead) }
    var gateClosesAt: Date { bestDeparture.addingTimeInterval(-gateCloseLead) }
    var bagsExpectedAt: Date { bestArrival.addingTimeInterval(bagsAllowance) }

    /// Every dated point in the flight's day, in order.
    var milestones: [FlightMilestone] {
        [
            FlightMilestone(kind: .checkIn, date: checkInOpensAt, isEstimated: true),
            FlightMilestone(kind: .boarding, date: boardingStartsAt, isEstimated: true),
            FlightMilestone(kind: .gateClose, date: gateClosesAt, isEstimated: true),
            FlightMilestone(kind: .departure, date: bestDeparture,
                            isEstimated: actualDeparture == nil && estimatedDeparture == nil),
            FlightMilestone(kind: .landing, date: bestArrival,
                            isEstimated: actualArrival == nil && estimatedArrival == nil),
            FlightMilestone(kind: .bags, date: bagsExpectedAt, isEstimated: true),
        ]
    }

    // MARK: Stage

    /// What's happening right now.
    ///
    /// Only cancellation and diversion short-circuit on the stored phase. A
    /// stored `.landed`/`.arrived` deliberately falls through to the clock:
    /// otherwise a flight that a provider marked "arrived" would sit on
    /// "Taxiing to gate" forever, because nothing would ever move it on.
    func stage(at now: Date = .now) -> FlightStage {
        switch phase {
        case .cancelled: return .cancelled
        case .diverted:  return .diverted
        default: break
        }

        let departure = bestDeparture
        let arrival = bestArrival

        // Down early — the provider says so before the ETA passed.
        if phase.isComplete, now < arrival { return .taxiingIn }

        if now >= arrival {
            if now < arrival.addingTimeInterval(Self.taxiInAllowance) { return .taxiingIn }
            if now < bagsExpectedAt { return .atGate }
            return .arrived
        }
        if now >= departure.addingTimeInterval(Self.taxiOutAllowance) {
            return now >= arrival.addingTimeInterval(-landingSoonWindow) ? .landingSoon : .airborne
        }
        if now >= departure { return .taxiingOut }
        if now >= gateClosesAt { return .gateClosing }
        if now >= boardingStartsAt { return .boarding }
        if now >= boardingStartsAt.addingTimeInterval(-Self.boardingSoonLead) { return .boardingSoon }
        if now >= checkInOpensAt { return .checkInOpen }
        return .scheduled
    }

    /// The next thing that hasn't happened yet, for the countdown on the card.
    /// `nil` once the flight is over or off.
    func nextMilestone(at now: Date = .now) -> FlightMilestone? {
        guard phase != .cancelled else { return nil }
        return milestones.first { $0.date > now }
    }
}
