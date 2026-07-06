import Foundation
import SwiftUI

/// A live FAA National Airspace System event affecting an airport —
/// the raw material for Airport Intelligence.
struct AirportEvent: Identifiable, Hashable {
    enum Kind: String {
        case groundStop = "Ground Stop"
        case groundDelay = "Ground Delay Program"
        case departureDelay = "Departure Delays"
        case arrivalDelay = "Arrival Delays"
        case closure = "Airport Closed"
    }

    var id = UUID()
    var airportIATA: String
    var kind: Kind
    var reason: String?             // FAA free text, e.g. "WX:Thunderstorms"
    var avgDelay: String?           // "45 minutes" / "1 hour and 12 minutes"
    var maxDelay: String?
    var endTime: String?            // FAA-provided end/reopen estimate

    var severityColor: Color {
        switch kind {
        case .closure, .groundStop: return Theme.red
        case .groundDelay: return Theme.orange
        case .departureDelay, .arrivalDelay: return Theme.orange
        }
    }

    var icon: String {
        switch kind {
        case .groundStop: return "hand.raised.fill"
        case .groundDelay: return "clock.badge.exclamationmark.fill"
        case .departureDelay: return "airplane.departure"
        case .arrivalDelay: return "airplane.arrival"
        case .closure: return "xmark.octagon.fill"
        }
    }

    /// Plain-English one-liner in the spirit of Flighty's Airport Intelligence.
    var summary: String {
        var s: String
        switch kind {
        case .groundStop:
            s = "Departures to this airport are held at their origin"
        case .groundDelay:
            s = "Inbound flights are being metered"
            if let avg = avgDelay { s += " — average delay \(avg)" }
        case .departureDelay:
            s = "Departures delayed"
            if let avg = avgDelay { s += " \(avg)" }
            if let mx = maxDelay { s += " (up to \(mx))" }
        case .arrivalDelay:
            s = "Arrivals delayed"
            if let avg = avgDelay { s += " \(avg)" }
            if let mx = maxDelay { s += " (up to \(mx))" }
        case .closure:
            s = "The airport is closed"
            if let end = endTime { s += " — estimated to reopen \(end)" }
        }
        if let reason = reasonDescription { s += ". Cause: \(reason)." }
        return s
    }

    /// FAA reasons look like "WX:Thunderstorms" or "VOL:Volume" — humanize.
    var reasonDescription: String? {
        guard var r = reason, !r.isEmpty else { return nil }
        r = r.replacingOccurrences(of: "WX:", with: "weather — ")
        r = r.replacingOccurrences(of: "WEATHER:", with: "weather — ")
        r = r.replacingOccurrences(of: "VOL:", with: "traffic volume — ")
        r = r.replacingOccurrences(of: "EQ:", with: "equipment — ")
        r = r.replacingOccurrences(of: "RWY:", with: "runway — ")
        r = r.replacingOccurrences(of: "STAFF:", with: "staffing — ")
        r = r.replacingOccurrences(of: "/", with: " / ")
        return r.lowercased()
    }
}
