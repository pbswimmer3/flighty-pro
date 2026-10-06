import Foundation

/// Everything the app is willing to interrupt you for.
///
/// Split into two families that behave differently:
///
/// * **Scheduled** alerts have a date the moment the flight is known, so they
///   are handed to iOS up front and fire whether or not the app is running.
///   That's the whole reason boarding alerts work at all without a server.
/// * **Change** alerts have no date — they exist because a refresh noticed the
///   flight moved. They can only fire while the app is awake to notice, which
///   is a real limitation and is stated plainly in Settings.
enum FlightAlert: String, CaseIterable, Codable {
    // Scheduled
    case checkIn
    case boarding
    case gateClose
    case departure
    case landingSoon
    case landing
    case bags

    // Change-triggered
    case delay
    case gateChange
    case disruption
    case aircraft
    case inbound

    var isScheduled: Bool {
        switch self {
        case .checkIn, .boarding, .gateClose, .departure, .landingSoon, .landing, .bags:
            return true
        case .delay, .gateChange, .disruption, .aircraft, .inbound:
            return false
        }
    }

    /// Which Settings toggle governs this alert. Twelve switches would be a
    /// worse screen than six.
    var group: Group {
        switch self {
        case .checkIn:                        return .checkIn
        case .boarding, .gateClose, .gateChange: return .gate
        case .departure, .landingSoon, .landing: return .movement
        case .bags:                           return .bags
        case .delay, .disruption, .inbound:   return .disruption
        case .aircraft:                       return .aircraft
        }
    }

    /// Alerts about doors and diversions are the ones worth breaking a Focus
    /// for. iOS ignores this without the time-sensitive entitlement, which is
    /// fine — it just delivers them normally.
    var isTimeSensitive: Bool {
        switch self {
        case .boarding, .gateClose, .gateChange, .disruption: return true
        default: return false
        }
    }

    enum Group: String, CaseIterable, Codable, Identifiable {
        case checkIn
        case gate
        case movement
        case bags
        case disruption
        case aircraft

        var id: String { rawValue }

        var title: String {
            switch self {
            case .checkIn:    return "Check-in"
            case .gate:       return "Boarding & gate"
            case .movement:   return "Departure & landing"
            case .bags:       return "Baggage claim"
            case .disruption: return "Delays & disruptions"
            case .aircraft:   return "Aircraft changes"
            }
        }

        var detail: String {
            switch self {
            case .checkIn:    return "When check-in opens, a day before you fly."
            case .gate:       return "Boarding starts, gate closing, and gate changes."
            case .movement:   return "Push-back, an hour before landing, and touchdown."
            case .bags:       return "Which belt your bags are coming out on."
            case .disruption: return "New delays, cancellations, diversions, and a late inbound aircraft."
            case .aircraft:   return "When the tail number or aircraft type assigned to your flight changes."
            }
        }

        var systemImage: String {
            switch self {
            case .checkIn:    return "checkmark.rectangle.portrait"
            case .gate:       return "door.left.hand.closed"
            case .movement:   return "airplane.departure"
            case .bags:       return "suitcase.fill"
            case .disruption: return "exclamationmark.triangle.fill"
            case .aircraft:   return "airplane.circle"
            }
        }
    }
}

/// Which alert groups are switched on. Persisted whole so adding a group later
/// defaults it on rather than silently off.
struct NotificationPreferences: Codable, Equatable {
    var isEnabled: Bool = true
    var disabledGroups: Set<FlightAlert.Group> = []

    func allows(_ alert: FlightAlert) -> Bool {
        isEnabled && !disabledGroups.contains(alert.group)
    }

    func allows(group: FlightAlert.Group) -> Bool {
        isEnabled && !disabledGroups.contains(group)
    }

    mutating func set(_ group: FlightAlert.Group, enabled: Bool) {
        if enabled { disabledGroups.remove(group) } else { disabledGroups.insert(group) }
    }
}
