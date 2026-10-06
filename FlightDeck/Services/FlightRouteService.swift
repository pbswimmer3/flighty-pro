import Foundation

/// "Where is that aircraft actually going?" — resolved from a callsign alone,
/// with no API key, anywhere in the world.
///
/// ADS-B tells us a callsign and a position; it says nothing about the route.
/// `adsbdb.com` maintains a free, keyless, community-maintained callsign →
/// route table, which is the only way this app can put "SFO → LHR" next to a
/// contact on the map. Two consequences worth keeping in mind:
///
/// * **It's a schedule table, not an observation.** It says which route that
///   flight number normally flies, not where this particular airframe is
///   heading today. Everything rendered from it is labelled as a lookup, never
///   as a live fact — same rule as the extrapolated positions on the map.
/// * **Coverage is uneven.** Airline flights resolve well; private, military
///   and freight callsigns frequently don't. A miss is normal and must render
///   as "route unknown", not as an error.
///
/// Doubles as the app's keyless international fallback: when a schedule
/// provider can't answer a flight-number lookup, this still knows the city
/// pair, which is enough to prefill a manual entry.
actor FlightRouteService {
    static let shared = FlightRouteService()

    struct Airport: Sendable, Hashable {
        var iata: String
        var name: String?
        var municipality: String?
        var countryISO: String?
    }

    struct Route: Sendable, Hashable {
        var callsignICAO: String
        var callsignIATA: String?
        var airlineName: String?
        var airlineIATA: String?
        var origin: Airport
        /// Populated for the tag-along leg of a multi-stop rotation.
        var midpoint: Airport?
        var destination: Airport

        /// "SFO → LHR", or "LHR → ROB → FNA" when there's a stop.
        var arrow: String {
            ([origin.iata] + [midpoint?.iata].compactMap { $0 } + [destination.iata])
                .joined(separator: " → ")
        }

        /// What the user's flight number would look like: "BA 137".
        var displayNumber: String? {
            guard let iata = callsignIATA,
                  let parsed = DemoFlightProvider.parseDesignator(iata) else { return nil }
            return "\(parsed.code) \(parsed.number)"
        }
    }

    private enum Entry {
        case hit(Route)
        case miss(at: Date)
    }

    private var cache: [String: Entry] = [:]
    /// Routes are effectively static, so a hit is cached for the session. A
    /// miss is retried after a while — a callsign the table hasn't learned yet
    /// shouldn't be written off forever.
    private let missRetryAfter: TimeInterval = 15 * 60

    /// Look up a callsign or flight designator. Accepts either form —
    /// "BAW117", "BA117", "BA 117" — because the map has ICAO callsigns and
    /// the add-flight screen has IATA designators, and the service resolves
    /// both.
    func route(for rawCallsign: String) async -> Route? {
        let key = rawCallsign
            .uppercased()
            .filter { $0.isLetter || $0.isNumber }

        // The endpoint rejects anything shorter than a real callsign, and
        // registrations of private aircraft ("N512DA") are never routes.
        guard key.count >= 3 else { return nil }

        switch cache[key] {
        case .hit(let route):
            return route
        case .miss(let at) where Date.now.timeIntervalSince(at) < missRetryAfter:
            return nil
        default:
            break
        }

        guard let url = URL(string: "https://api.adsbdb.com/v0/callsign/\(key)") else { return nil }
        var request = URLRequest(url: url)
        request.timeoutInterval = 12

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            // 404 "unknown callsign" and 400 "invalid callsign" both come back
            // with a plain string in `response`, so decoding would fail anyway;
            // checking the status first just keeps the intent legible.
            if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
                cache[key] = .miss(at: .now)
                return nil
            }
            let decoded = try JSONDecoder().decode(Envelope.self, from: data)
            guard let route = decoded.response.flightroute?.route else {
                cache[key] = .miss(at: .now)
                return nil
            }
            cache[key] = .hit(route)
            return route
        } catch {
            cache[key] = .miss(at: .now)
            return nil
        }
    }

    /// Fire-and-forget warm-up so a tap on the map renders the route
    /// immediately rather than after a round trip.
    func prefetch(_ callsigns: [String]) async {
        for callsign in callsigns.prefix(6) {
            _ = await route(for: callsign)
        }
    }

    // MARK: - Wire format

    private struct Envelope: Decodable {
        var response: Response

        /// `response` is an object on success and a bare string ("unknown
        /// callsign") on failure, so it has to decode leniently or every miss
        /// throws.
        struct Response: Decodable {
            var flightroute: WireRoute?

            init(from decoder: Decoder) throws {
                guard let container = try? decoder.container(keyedBy: CodingKeys.self) else {
                    flightroute = nil
                    return
                }
                flightroute = try? container.decodeIfPresent(WireRoute.self, forKey: .flightroute)
            }

            private enum CodingKeys: String, CodingKey { case flightroute }
        }
    }

    private struct WireRoute: Decodable {
        var callsign: String?
        var callsign_icao: String?
        var callsign_iata: String?
        var airline: WireAirline?
        var origin: WireAirport?
        var midpoint: WireAirport?
        var destination: WireAirport?

        var route: Route? {
            guard let origin = origin?.airport, let destination = destination?.airport else { return nil }
            return Route(callsignICAO: callsign_icao ?? callsign ?? "",
                         callsignIATA: callsign_iata,
                         airlineName: airline?.name,
                         airlineIATA: airline?.iata,
                         origin: origin,
                         midpoint: midpoint?.airport,
                         destination: destination)
        }
    }

    private struct WireAirline: Decodable {
        var name: String?
        var icao: String?
        var iata: String?
    }

    private struct WireAirport: Decodable {
        var iata_code: String?
        var icao_code: String?
        var name: String?
        var municipality: String?
        var country_iso_name: String?

        var airport: Airport? {
            guard let iata = iata_code, !iata.isEmpty else { return nil }
            return Airport(iata: iata,
                           name: name,
                           municipality: municipality,
                           countryISO: country_iso_name)
        }
    }
}
