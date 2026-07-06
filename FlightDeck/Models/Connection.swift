import Foundation
import SwiftUI

/// Risk rating for a connection, mirroring Flighty's four buckets.
enum ConnectionRisk: String, CaseIterable {
    case relaxed = "Relaxed"
    case normal = "Normal"
    case tight = "Tight"
    case risky = "Risky"
    case misconnect = "Misconnect"

    var color: Color {
        switch self {
        case .relaxed: return Theme.green
        case .normal: return Theme.accent
        case .tight: return Theme.orange
        case .risky: return Theme.red
        case .misconnect: return Theme.red
        }
    }

    var explanation: String {
        switch self {
        case .relaxed: return "Plenty of buffer — grab a coffee."
        case .normal: return "A comfortable connection under normal conditions."
        case .tight: return "Doable, but head straight to your next gate."
        case .risky: return "Below or barely above the minimum connection time. Talk to an agent about backups."
        case .misconnect: return "Your inbound flight now arrives after your next departure. Rebooking is likely required."
        }
    }
}

/// The Connection Assistant's full assessment of an inbound → outbound pair.
struct ConnectionAssessment {
    var inbound: Flight
    var outbound: Flight
    var airport: Airport?

    /// Live layover: estimated arrival of leg 1 → estimated departure of leg 2.
    var layoverMinutes: Int {
        Int(outbound.bestDeparture.timeIntervalSince(inbound.bestArrival) / 60)
    }

    /// Layover as originally scheduled — used to explain what changed.
    var scheduledLayoverMinutes: Int {
        Int(outbound.scheduledDeparture.timeIntervalSince(inbound.scheduledArrival) / 60)
    }

    var isInternational: Bool {
        // International rules apply if either leg crosses a border relative
        // to the connecting airport's country.
        guard let apt = airport else { return false }
        let db = AirportDatabase.shared
        let origin = db.airport(iata: inbound.originIATA)
        let dest = db.airport(iata: outbound.destinationIATA)
        return (origin?.country ?? apt.country) != apt.country
            || (dest?.country ?? apt.country) != apt.country
    }

    var minimumConnectionMinutes: Int {
        guard let apt = airport else { return isInternational ? 90 : 45 }
        var mct = isInternational ? apt.mctInternational : apt.mctDomestic
        if terminalChange { mct += 15 }   // penalty for changing terminals
        return mct
    }

    var terminalChange: Bool {
        guard let a = inbound.arrivalTerminal, let d = outbound.departureTerminal else { return false }
        return a != d
    }

    var risk: ConnectionRisk {
        let m = layoverMinutes
        let mct = minimumConnectionMinutes
        if m <= 0 { return .misconnect }
        if m < mct { return .risky }
        if m < mct + 30 { return .tight }
        if m < mct + 90 { return .normal }
        return .relaxed
    }

    /// Minutes of layover lost (positive) or gained vs. schedule.
    var bufferChangeMinutes: Int { layoverMinutes - scheduledLayoverMinutes }

    var layoverDescription: String {
        let m = max(layoverMinutes, 0)
        return m >= 60 ? "\(m / 60)h \(m % 60)m" : "\(m)m"
    }
}
