import Foundation
import SwiftUI

/// A single delay-risk signal for a flight (our lightweight take on
/// Flighty's ML delay predictions — heuristic, but built from the same
/// classes of evidence: late inbound aircraft, FAA programs, bad weather).
struct IntelSignal: Identifiable, Hashable {
    enum Severity { case info, caution, warning }

    var id = UUID()
    var severity: Severity
    var icon: String
    var title: String
    var detail: String

    var color: Color {
        switch severity {
        case .info: return Theme.accent
        case .caution: return Theme.orange
        case .warning: return Theme.red
        }
    }
}

/// Gathers all available evidence about a flight and produces signals.
enum FlightIntel {

    static func signals(for flight: Flight) async -> [IntelSignal] {
        var signals: [IntelSignal] = []
        let db = AirportDatabase.shared
        let origin = db.airport(iata: flight.originIATA)
        let destination = db.airport(iata: flight.destinationIATA)

        // 1) Late inbound aircraft ("Where's my plane").
        if let inbound = flight.inbound, inbound.isDelayed, !flight.effectivePhase.isAirborne,
           !flight.effectivePhase.isComplete {
            signals.append(IntelSignal(
                severity: inbound.delayMinutes > 30 ? .warning : .caution,
                icon: "airplane.arrival",
                title: "Inbound aircraft running \(inbound.delayMinutes) min late",
                detail: "Your plane (\(inbound.flightNumber) from \(inbound.originIATA)) hasn't arrived yet. Departure delays often follow."))
        }

        // 2) FAA programs at origin / destination (US only).
        if let origin, origin.isUS {
            for event in await FAAStatusService.shared.events(for: origin.iata) {
                signals.append(IntelSignal(
                    severity: event.kind == .groundStop || event.kind == .closure ? .warning : .caution,
                    icon: event.icon,
                    title: "\(event.kind.rawValue) at \(origin.iata)",
                    detail: event.summary))
            }
        }
        if let destination, destination.isUS {
            for event in await FAAStatusService.shared.events(for: destination.iata)
            where event.kind == .groundStop || event.kind == .arrivalDelay || event.kind == .closure {
                signals.append(IntelSignal(
                    severity: .caution,
                    icon: event.icon,
                    title: "\(event.kind.rawValue) at \(destination.iata)",
                    detail: event.summary))
            }
        }

        // 3) IFR/LIFR weather at either end.
        for airport in [origin, destination].compactMap({ $0 }) {
            if let metar = await WeatherService.shared.metar(for: airport),
               ["IFR", "LIFR"].contains((metar.fltCat ?? "").uppercased()) {
                var detail = "Low visibility/ceilings (\(metar.fltCat ?? "IFR") conditions)"
                if let wx = metar.conditionsSummary { detail += " — \(wx)" }
                detail += ". Expect reduced arrival rates."
                signals.append(IntelSignal(
                    severity: .caution,
                    icon: "cloud.fog.fill",
                    title: "Poor weather at \(airport.iata)",
                    detail: detail))
            }
        }

        // 4) Confirmed delay from the data itself.
        if flight.isDelayed, flight.phase != .cancelled {
            signals.append(IntelSignal(
                severity: flight.arrivalDelayMinutes >= 45 ? .warning : .caution,
                icon: "clock.badge.exclamationmark",
                title: "Running \(max(flight.departureDelayMinutes, flight.arrivalDelayMinutes)) min behind schedule",
                detail: "Times shown reflect the latest estimates."))
        }

        if signals.isEmpty {
            signals.append(IntelSignal(
                severity: .info,
                icon: "checkmark.seal.fill",
                title: "No delay signals",
                detail: "Inbound aircraft, airport programs, and weather all look clear right now."))
        }
        return signals
    }
}
