import Foundation

/// Something that moved between two snapshots of the same flight, phrased the
/// way it should read on a lock screen.
///
/// A pure function over two `Flight` values, deliberately: the alerting rules
/// are the easiest part of this app to get subtly wrong, and keeping them out
/// of the store means they can be reasoned about — and eventually tested —
/// without a notification centre anywhere near them.
struct FlightChange: Identifiable, Equatable {
    var alert: FlightAlert
    var title: String
    var body: String

    var id: String { "\(alert.rawValue)-\(title)-\(body)" }

    /// How far a time has to move before it's worth a notification. Estimates
    /// jitter by a few minutes on every refresh; alerting on that would train
    /// people to ignore the app.
    static let materialMinutes = 10

    static func between(_ old: Flight, _ new: Flight) -> [FlightChange] {
        var changes: [FlightChange] = []
        let number = new.displayNumber

        // MARK: Disruption

        if old.phase != .cancelled, new.phase == .cancelled {
            changes.append(FlightChange(
                alert: .disruption,
                title: "\(number) cancelled",
                body: "\(new.originIATA) → \(new.destinationIATA) has been cancelled. Check with \(new.airlineName) for rebooking."))
        }
        if old.phase != .diverted, new.phase == .diverted {
            changes.append(FlightChange(
                alert: .disruption,
                title: "\(number) diverted",
                body: "The flight is no longer heading to \(new.destinationIATA)."))
        }

        // MARK: Times
        //
        // Reported against the *scheduled* time, not the previous estimate, so
        // the message says how late the flight is rather than how much the
        // guess moved since the last poll.

        let departureShift = new.departureDelayMinutes - old.departureDelayMinutes
        if abs(departureShift) >= materialMinutes, new.phase != .cancelled {
            let local = Fmt.time(new.bestDeparture, airportIATA: new.originIATA)
            changes.append(FlightChange(
                alert: .delay,
                title: departureShift > 0
                    ? "\(number) delayed \(Fmt.delta(new.departureDelayMinutes))"
                    : "\(number) is leaving earlier",
                body: "Now departing \(local) from \(new.originIATA)."))
        }

        let arrivalShift = new.arrivalDelayMinutes - old.arrivalDelayMinutes
        // Only worth its own alert when the departure didn't already explain it.
        if abs(arrivalShift) >= materialMinutes,
           abs(arrivalShift - departureShift) >= materialMinutes,
           new.phase != .cancelled {
            let local = Fmt.time(new.bestArrival, airportIATA: new.destinationIATA)
            changes.append(FlightChange(
                alert: .delay,
                title: arrivalShift > 0
                    ? "\(number) arriving \(Fmt.delta(new.arrivalDelayMinutes))"
                    : "\(number) arriving earlier",
                body: "New arrival \(local) at \(new.destinationIATA)."))
        }

        // MARK: Gates

        if let gate = new.departureGate, gate != old.departureGate {
            let terminal = new.departureTerminal.map { "Terminal \($0), " } ?? ""
            changes.append(FlightChange(
                alert: .gateChange,
                title: old.departureGate == nil
                    ? "\(number) gate assigned"
                    : "\(number) gate change",
                body: old.departureGate.map { "\(terminal)gate \(gate) — moved from \($0)." }
                    ?? "\(terminal)gate \(gate) at \(new.originIATA)."))
        }
        if let gate = new.arrivalGate, gate != old.arrivalGate, old.arrivalGate != nil {
            changes.append(FlightChange(
                alert: .gateChange,
                title: "\(number) arrival gate change",
                body: "Now arriving at gate \(gate) in \(new.destinationIATA)."))
        }

        // MARK: Bags

        if let belt = new.baggageClaim, belt != old.baggageClaim {
            changes.append(FlightChange(
                alert: .bags,
                title: "Baggage claim \(belt)",
                body: "\(number) bags are coming out at claim \(belt) in \(new.destinationIATA)."))
        }

        // MARK: Aircraft

        if let tail = new.tailNumber, tail != old.tailNumber, old.tailNumber != nil {
            let type = new.aircraftType.map { " (\($0))" } ?? ""
            changes.append(FlightChange(
                alert: .aircraft,
                title: "\(number) aircraft change",
                body: "Now operated by \(tail)\(type)."))
        } else if let type = new.aircraftType, type != old.aircraftType, old.aircraftType != nil {
            changes.append(FlightChange(
                alert: .aircraft,
                title: "\(number) aircraft change",
                body: "Now scheduled to be a \(type)."))
        }

        // MARK: Inbound aircraft
        //
        // The single biggest predictor of a departure delay, and the one
        // Flighty leans on hardest — worth an alert of its own, well before
        // the airline moves the departure time.

        if let inbound = new.inbound,
           inbound.isDelayed,
           inbound.delayMinutes - (old.inbound?.delayMinutes ?? 0) >= materialMinutes,
           !new.effectivePhase.isAirborne {
            changes.append(FlightChange(
                alert: .inbound,
                title: "Your inbound aircraft is late",
                body: "\(inbound.flightNumber) from \(inbound.originIATA) is running \(Fmt.delta(inbound.delayMinutes)) into \(new.originIATA). \(number) may be affected."))
        }

        return changes
    }
}
