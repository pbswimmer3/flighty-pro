import Foundation
import CoreLocation

/// An airport from the bundled database — either the curated list
/// (Resources/airports.json) or the world fallback behind it
/// (Resources/airports-world.json). See `AirportDatabase`.
struct Airport: Identifiable, Codable, Hashable {
    var iata: String                // "SFO"
    var icao: String                // "KSFO"
    var name: String                // "San Francisco International"
    var city: String
    var country: String             // ISO-ish country name, "United States"
    var lat: Double
    var lon: Double
    var tz: String                  // IANA identifier, "America/Los_Angeles"

    /// Minimum connection times in minutes (rule-of-thumb values used by the
    /// Connection Assistant; airline-published MCTs vary by itinerary).
    var mctDomestic: Int
    var mctInternational: Int

    /// Short free-text terminal overview shown on the airport page.
    var terminals: String?

    /// `true` for airports that came from the world fallback list, which only
    /// knows where an airport is and what time it is there. Their connection
    /// times are the rule-of-thumb defaults below, not researched values, and
    /// the UI says so. Optional so the curated JSON decodes without the key.
    var isFromWorldList: Bool?

    /// What a connection at an airport we know nothing else about is assumed
    /// to need. Matches the fallback `Connection` already used for an airport
    /// missing entirely, so the risk call doesn't change depending on which
    /// list an airport happened to come from.
    static let typicalMCTDomestic = 45
    static let typicalMCTInternational = 90

    /// Whether the minimum connection times are researched rather than defaults.
    var hasResearchedConnectionTimes: Bool { isFromWorldList != true }

    var id: String { iata }

    var coordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: lat, longitude: lon)
    }

    var timeZone: TimeZone { TimeZone(identifier: tz) ?? .current }

    var isUS: Bool { country == "United States" }

    /// "2:47 PM" in the airport's local time.
    func localTimeString(_ date: Date = .now) -> String {
        let f = DateFormatter()
        f.timeStyle = .short
        f.timeZone = timeZone
        return f.string(from: date)
    }
}
