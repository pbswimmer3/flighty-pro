import Foundation

/// Airport Intelligence data source #1: the FAA's public National Airspace
/// System status feed (nasstatus.faa.gov). Keyless. Lists ground stops,
/// ground delay programs, arrival/departure delays, and closures — US only.
///
/// The feed is XML; parsing is deliberately tolerant: we walk elements with a
/// tiny state machine and any structure we don't recognize simply yields no
/// events rather than an error.
actor FAAStatusService {
    static let shared = FAAStatusService()

    private var cache: (events: [AirportEvent], fetched: Date)?
    private let cacheTTL: TimeInterval = 120

    func events(for iata: String) async -> [AirportEvent] {
        let all = await allEvents()
        return all.filter { $0.airportIATA == iata.uppercased() }
    }

    func allEvents() async -> [AirportEvent] {
        if let cache, Date.now.timeIntervalSince(cache.fetched) < cacheTTL {
            return cache.events
        }
        guard let url = URL(string: "https://nasstatus.faa.gov/api/airport-status-information") else {
            return []
        }
        do {
            var request = URLRequest(url: url)
            request.setValue("application/xml", forHTTPHeaderField: "Accept")
            let (data, _) = try await URLSession.shared.data(for: request)
            let parser = FAAXMLParser()
            let events = parser.parse(data: data)
            cache = (events, .now)
            return events
        } catch {
            return []
        }
    }
}

/// Minimal, defensive parser for the FAA airport-status XML.
private final class FAAXMLParser: NSObject, XMLParserDelegate {
    private var events: [AirportEvent] = []

    // Current context while walking the tree.
    private var currentDelayTypeName = ""
    private var currentText = ""
    private var airport = ""
    private var reason: String?
    private var avg: String?
    private var max: String?
    private var end: String?
    private var arrivalDeparture: String?   // "Arrival"/"Departure" attribute
    private var minDelay: String?
    private var maxDelay: String?

    func parse(data: Data) -> [AirportEvent] {
        let parser = XMLParser(data: data)
        parser.delegate = self
        parser.parse()
        return events
    }

    func parser(_ parser: XMLParser, didStartElement name: String, namespaceURI: String?,
                qualifiedName: String?, attributes: [String: String] = [:]) {
        currentText = ""
        switch name {
        case "Program", "Ground_Delay", "Delay", "Airport":
            airport = ""; reason = nil; avg = nil; max = nil; end = nil
            arrivalDeparture = nil; minDelay = nil; maxDelay = nil
        case "Arrival_Departure":
            arrivalDeparture = attributes["Type"] ?? attributes["type"]
        default:
            break
        }
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        currentText += string
    }

    func parser(_ parser: XMLParser, didEndElement name: String, namespaceURI: String?,
                qualifiedName: String?) {
        let text = currentText.trimmingCharacters(in: .whitespacesAndNewlines)
        switch name {
        case "Name":
            currentDelayTypeName = text
        case "ARPT":
            airport = text
        case "Reason":
            reason = text
        case "Avg":
            avg = text
        case "Max":
            maxDelay = text; max = text
        case "Min":
            minDelay = text
        case "End_Time", "Reopen":
            end = text
        case "Program":
            append(kind: .groundStop)
        case "Ground_Delay":
            append(kind: .groundDelay)
        case "Delay":
            let kind: AirportEvent.Kind =
                (arrivalDeparture ?? "").lowercased().hasPrefix("arr") ? .arrivalDelay : .departureDelay
            // The general-delay entries carry Min/Max instead of Avg.
            if avg == nil, let mn = minDelay, let mx = maxDelay {
                avg = "\(mn)–\(mx)"
            }
            append(kind: kind)
        case "Airport":
            // Only closure lists nest ARPT directly inside <Airport>.
            if currentDelayTypeName.localizedCaseInsensitiveContains("Closure") {
                append(kind: .closure)
            }
        default:
            break
        }
        currentText = ""
    }

    private func append(kind: AirportEvent.Kind) {
        guard airport.count == 3 else { return }
        events.append(AirportEvent(
            airportIATA: airport.uppercased(),
            kind: kind, reason: reason,
            avgDelay: avg, maxDelay: max, endTime: end))
        airport = ""
    }
}
