import Foundation

/// Real flight schedules & status via AeroDataBox (RapidAPI).
/// Free tier is plenty for personal use; the key lives in SettingsStore.
struct AeroDataBoxProvider: FlightDataProvider {
    let apiKey: String

    private static let host = "aerodatabox.p.rapidapi.com"

    /// How far ahead the flight-status endpoint reliably answers on the free
    /// and Basic plans — and therefore how far ahead a flight can be
    /// *confirmed*. It is not a limit on adding one: past this, a search still
    /// asks for the real date first (higher plans and published schedules can
    /// reach further), and only if that comes back empty does it fall back to
    /// projecting this week's timetable. See `ScheduleProjection`.
    ///
    /// This used to be a hard wall checked before any request, which made
    /// "only flights within a week" a property of the app rather than of the
    /// data — the feed was never even asked.
    static let liveWindowDays = 7

    /// Whole calendar days from today to `date` (negative in the past).
    static func daysAhead(of date: Date, now: Date = .now, calendar: Calendar = .current) -> Int {
        calendar.dateComponents([.day],
                                from: calendar.startOfDay(for: now),
                                to: calendar.startOfDay(for: date)).day ?? 0
    }

    /// True for a future date the live feed may not reach — the only case
    /// where projecting from this week is worth trying.
    static func isBeyondLiveWindow(_ date: Date, now: Date = .now) -> Bool {
        daysAhead(of: date, now: now) > liveWindowDays
    }

    func searchFlights(number: String, date: Date) async throws -> [Flight] {
        guard !apiKey.isEmpty else { throw FlightDataError.missingAPIKey }
        guard let designator = DemoFlightProvider.parseDesignator(number) else {
            throw FlightDataError.notFound
        }
        // The date picker hands over an instant; the service wants the local
        // calendar day the user picked, which is the day in *their* calendar.
        let day = Calendar.current.dateComponents([.year, .month, .day], from: date)
        return try await search(designator, on: day, projectIfBeyondWindow: true)
    }

    /// Ask for the real day; if that fails on a day past the live window, try
    /// projecting from the same weekday this week.
    private func search(_ designator: (code: String, number: String),
                        on day: DateComponents,
                        projectIfBeyondWindow: Bool) async throws -> [Flight] {
        do {
            return try await fetch(designator, on: day)
        } catch let error as FlightDataError {
            guard projectIfBeyondWindow,
                  error.isWorthAddingManually,
                  let target = Calendar.current.date(from: day),
                  Self.isBeyondLiveWindow(target)
            else { throw error }

            if let projected = await project(designator, onto: day) { return projected }
            // Nothing this week either. A bare "not found" or an unreadable
            // body would hide the real reason, which is the date.
            switch error {
            case .notFound, .decoding: throw FlightDataError.dateOutOfRange
            default: throw error
            }
        }
    }

    /// Same weekday this coming week, then last week. Sequential on purpose:
    /// the first hit ends it, and free tiers rate-limit bursts hard.
    private func project(_ designator: (code: String, number: String),
                         onto target: DateComponents) async -> [Flight]? {
        for reference in ScheduleProjection.referenceDays(for: target) {
            guard let flights = try? await fetch(designator, on: reference) else { continue }
            let projected = flights.compactMap {
                ScheduleProjection.project($0, from: reference, onto: target)
            }
            if !projected.isEmpty { return projected }
        }
        return nil
    }

    /// One request for one local day.
    private func fetch(_ designator: (code: String, number: String),
                       on day: DateComponents) async throws -> [Flight] {
        guard let year = day.year, let month = day.month, let dayOfMonth = day.day else {
            throw FlightDataError.notFound
        }
        let dateString = String(format: "%04d-%02d-%02d", year, month, dayOfMonth)

        let numberPath = "\(designator.code)\(designator.number)"
        var components = URLComponents()
        components.scheme = "https"
        components.host = Self.host
        components.path = "/flights/number/\(numberPath)/\(dateString)"
        components.queryItems = [URLQueryItem(name: "withAircraftImage", value: "false"),
                                 URLQueryItem(name: "withLocation", value: "false")]
        guard let url = components.url else { throw FlightDataError.notFound }

        var request = URLRequest(url: url)
        request.setValue(apiKey, forHTTPHeaderField: "X-RapidAPI-Key")
        request.setValue(Self.host, forHTTPHeaderField: "X-RapidAPI-Host")

        let (data, response): (Data, URLResponse)
        do {
            (data, response) = try await URLSession.shared.data(for: request)
        } catch {
            throw FlightDataError.network(error.localizedDescription)
        }
        if let http = response as? HTTPURLResponse {
            if http.statusCode == 404 { throw FlightDataError.notFound }
            if http.statusCode == 401 || http.statusCode == 403 { throw FlightDataError.missingAPIKey }
            guard (200..<300).contains(http.statusCode) else {
                // RapidAPI and AeroDataBox both put a human-readable reason in
                // the body. Passing it through beats "HTTP 400".
                if let message = Self.serviceMessage(from: data) {
                    throw FlightDataError.service(message)
                }
                throw FlightDataError.network("HTTP \(http.statusCode)")
            }
        }

        // A 200 with nothing in it is a "no flights that day", not a parse
        // failure, and must not read like one.
        guard !Self.isEffectivelyEmpty(data) else { throw FlightDataError.notFound }

        guard let decoded = Self.decodeFlights(from: data) else {
            // A 2xx whose body still isn't a flight list is almost always the
            // service explaining itself. Show what it said.
            if let message = Self.serviceMessage(from: data) {
                throw FlightDataError.service(message)
            }
            throw FlightDataError.decoding(Self.excerpt(of: data))
        }

        let flights = decoded.compactMap { Self.convert($0) }
        guard !flights.isEmpty else { throw FlightDataError.notFound }
        return flights
    }

    // MARK: - Response shapes
    //
    // The endpoint has returned a bare array historically and an object with a
    // `flights` key since the schema revision, and which one you get depends on
    // the plan and the marketplace the key came from. Accepting both is a few
    // lines; guessing wrong is a screen that says nothing useful.

    static func decodeFlights(from data: Data) -> [ADBFlight]? {
        let decoder = JSONDecoder()
        if let array = try? decoder.decode([Lenient<ADBFlight>].self, from: data) {
            return array.compactMap(\.value)
        }
        if let envelope = try? decoder.decode(ADBEnvelope.self, from: data) {
            return envelope.flights.compactMap(\.value)
        }
        return nil
    }

    struct ADBEnvelope: Decodable {
        var flights: [Lenient<ADBFlight>]

        private enum CodingKeys: String, CodingKey { case flights, items, data }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            flights = try container.decodeIfPresent([Lenient<ADBFlight>].self, forKey: .flights)
                ?? container.decodeIfPresent([Lenient<ADBFlight>].self, forKey: .items)
                ?? container.decode([Lenient<ADBFlight>].self, forKey: .data)
        }
    }

    static func isEffectivelyEmpty(_ data: Data) -> Bool {
        let trimmed = String(decoding: data, as: UTF8.self)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty || trimmed == "[]" || trimmed == "{}" || trimmed == "null"
    }

    /// `{"message": "..."}` from RapidAPI, `{"error": "..."}` from some
    /// gateways — either way, one sentence meant to be read by a person.
    static func serviceMessage(from data: Data) -> String? {
        struct Wire: Decodable {
            var message: String?
            var error: String?
            var detail: String?
        }
        guard let wire = try? JSONDecoder().decode(Wire.self, from: data),
              let text = wire.message ?? wire.error ?? wire.detail,
              !text.isEmpty else { return nil }
        return text
    }

    /// A short, single-line excerpt for the error message. Long enough to
    /// recognise an HTML error page or a JSON envelope; short enough for a
    /// footnote.
    static func excerpt(of data: Data, limit: Int = 120) -> String? {
        let text = String(decoding: data, as: UTF8.self)
            .replacingOccurrences(of: "\n", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return nil }
        return text.count <= limit ? text : String(text.prefix(limit)) + "…"
    }

    func refresh(flight: Flight) async throws -> Flight {
        guard !apiKey.isEmpty else { throw FlightDataError.missingAPIKey }
        guard let designator = DemoFlightProvider.parseDesignator(
            "\(flight.airlineCode)\(flight.flightNumber)") else {
            throw FlightDataError.notFound
        }
        // The departure's own local day, not the phone's: a 7:59 PM SNA
        // departure is the 10th in California even if the phone is in London.
        let day = flight.originCalendar.dateComponents([.year, .month, .day],
                                                       from: flight.scheduledDeparture)
        // A flight that's already a projection may be re-projected (that picks
        // up timetable changes); a real one must never be silently swapped
        // for a guess.
        let results = try await search(designator, on: day,
                                       projectIfBeyondWindow: flight.isScheduleProjected)
        // Match on route since a designator can fly multiple segments per day.
        var updated = results.first {
            $0.originIATA == flight.originIATA && $0.destinationIATA == flight.destinationIATA
        } ?? results[0]
        updated.id = flight.id   // preserve identity in the store
        // User-entered: no provider knows it, and a refresh used to wipe it.
        updated.seat = flight.seat
        return updated
    }

    // MARK: - Wire models (subset of the AeroDataBox schema, all optional)

    struct ADBFlight: Decodable {
        var number: String?
        var callSign: String?
        var status: String?
        var departure: ADBMovement?
        var arrival: ADBMovement?
        var aircraft: ADBAircraft?
        var airline: ADBAirline?
    }

    struct ADBMovement: Decodable {
        var airport: ADBAirport?
        var scheduledTime: ADBTime?
        var revisedTime: ADBTime?
        var runwayTime: ADBTime?
        var terminal: String?
        var gate: String?
        var baggageBelt: String?
    }

    struct ADBAirport: Decodable { var iata: String?; var icao: String?; var name: String? }
    struct ADBTime: Decodable { var utc: String?; var local: String? }
    struct ADBAircraft: Decodable { var model: String?; var reg: String? }
    struct ADBAirline: Decodable { var name: String?; var iata: String? }

    // MARK: - Conversion

    static func convert(_ adb: ADBFlight) -> Flight? {
        guard
            let originIATA = adb.departure?.airport?.iata,
            let destIATA = adb.arrival?.airport?.iata,
            let schedDep = parseTime(adb.departure?.scheduledTime),
            let schedArr = parseTime(adb.arrival?.scheduledTime)
        else { return nil }

        let (code, num) = splitNumber(adb.number ?? "")

        var f = Flight(
            airlineName: adb.airline?.name ?? DemoFlightProvider.airlineName(for: code),
            airlineCode: adb.airline?.iata ?? code,
            flightNumber: num,
            callSign: adb.callSign?.replacingOccurrences(of: " ", with: ""),
            originIATA: originIATA,
            destinationIATA: destIATA,
            scheduledDeparture: schedDep,
            scheduledArrival: schedArr,
            departureTerminal: adb.departure?.terminal,
            departureGate: adb.departure?.gate,
            arrivalTerminal: adb.arrival?.terminal,
            arrivalGate: adb.arrival?.gate,
            baggageClaim: adb.arrival?.baggageBelt,
            aircraftModel: adb.aircraft?.model,
            registration: adb.aircraft?.reg)

        f.estimatedDeparture = parseTime(adb.departure?.revisedTime)
        f.estimatedArrival = parseTime(adb.arrival?.revisedTime)
        if let runway = parseTime(adb.departure?.runwayTime) { f.actualDeparture = runway }
        if let runway = parseTime(adb.arrival?.runwayTime) { f.actualArrival = runway }
        f.phase = phase(from: adb.status)
        f.isLiveData = true
        f.lastUpdated = .now
        return f
    }

    static func phase(from status: String?) -> FlightPhase {
        switch (status ?? "").lowercased() {
        case "boarding", "gateclosed": return .boarding
        case "departed", "enroute", "en route", "approaching": return .enRoute
        case "arrived": return .arrived
        case "canceled", "cancelled", "canceleduncertain": return .cancelled
        case "diverted": return .diverted
        default: return .scheduled
        }
    }

    /// AeroDataBox UTC times look like "2026-07-06 14:20Z";
    /// local times like "2026-07-06 08:20-06:00". Prefer UTC.
    static func parseTime(_ t: ADBTime?) -> Date? {
        guard let t else { return nil }
        if let utc = t.utc {
            let df = DateFormatter()
            df.locale = Locale(identifier: "en_US_POSIX")
            df.dateFormat = "yyyy-MM-dd HH:mm'Z'"
            df.timeZone = TimeZone(identifier: "UTC")
            if let d = df.date(from: utc) { return d }
        }
        if let local = t.local {
            let iso = local.replacingOccurrences(of: " ", with: "T")
            let f = ISO8601DateFormatter()
            f.formatOptions = [.withInternetDateTime]
            if let d = f.date(from: iso) { return d }
        }
        return nil
    }

    static func splitNumber(_ full: String) -> (String, String) {
        if let parsed = DemoFlightProvider.parseDesignator(full) { return parsed }
        return ("??", full)
    }
}
