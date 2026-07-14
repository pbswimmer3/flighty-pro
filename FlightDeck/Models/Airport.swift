import Foundation
import CoreLocation

/// An airport from the bundled database (Resources/airports.json).
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
