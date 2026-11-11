import Foundation

/// Zero-configuration provider. Generates realistic flights *relative to the
/// current clock* so the app always demos well: something in the air right
/// now, a tight connection later today, a flight tomorrow, one landed
/// yesterday. Statuses evolve as real time passes.
struct DemoFlightProvider: FlightDataProvider {

    func searchFlights(number: String, date: Date) async throws -> [Flight] {
        // Pretend any searched flight exists: fabricate a plausible flight on
        // that date so the add-flight flow is testable end to end.
        try? await Task.sleep(nanoseconds: 400_000_000)  // feel like a network call
        let parsed = Self.parseDesignator(number)
        guard let parsed else { throw FlightDataError.notFound }

        let cal = Calendar.current
        var dep = cal.startOfDay(for: date)
        dep = cal.date(byAdding: .hour, value: 13, to: dep) ?? dep
        dep = cal.date(byAdding: .minute, value: (abs(number.hashValue) % 4) * 15, to: dep) ?? dep

        let routes = [("SFO", "JFK", 5.4), ("LAX", "ORD", 4.1), ("SEA", "DEN", 2.6),
                      ("ATL", "MIA", 1.9), ("BOS", "LHR", 6.6), ("DFW", "LAS", 2.7)]
        let route = routes[abs(parsed.number.hashValue) % routes.count]

        var f = Flight(
            airlineName: Self.airlineName(for: parsed.code),
            airlineCode: parsed.code,
            flightNumber: parsed.number,
            callSign: nil,
            originIATA: route.0,
            destinationIATA: route.1,
            scheduledDeparture: dep,
            scheduledArrival: dep.addingTimeInterval(route.2 * 3600),
            departureTerminal: "2", departureGate: "D\(1 + abs(parsed.number.hashValue) % 20)",
            arrivalTerminal: "4", arrivalGate: "B\(1 + abs(parsed.code.hashValue) % 30)",
            baggageClaim: "\(3 + abs(parsed.number.hashValue) % 9)",
            aircraftModel: "Boeing 737-900ER", registration: "N\(400 + abs(parsed.number.hashValue) % 500)DM")
        f.isLiveData = false
        return [f]
    }

    func refresh(flight: Flight) async throws -> Flight {
        var f = flight
        f.phase = f.effectivePhase
        f.lastUpdated = .now
        return f
    }

    // MARK: - Sample trip

    /// The showcase set added by "Add Sample Trip".
    static func sampleFlights(now: Date = .now) -> [Flight] {
        var flights: [Flight] = []

        // 1) In the air right now: SFO → JFK, departed 2h ago, delayed 25m.
        var inAir = Flight(
            airlineName: "Delta Air Lines", airlineCode: "DL", flightNumber: "482",
            callSign: "DAL482",
            originIATA: "SFO", destinationIATA: "JFK",
            scheduledDeparture: now.addingTimeInterval(-2.4 * 3600),
            scheduledArrival: now.addingTimeInterval(2.9 * 3600),
            departureTerminal: "1", departureGate: "C11",
            arrivalTerminal: "4", arrivalGate: "B24", baggageClaim: "7",
            aircraftModel: "Airbus A321neo", registration: "N512DA")
        inAir.estimatedDeparture = inAir.scheduledDeparture.addingTimeInterval(25 * 60)
        inAir.actualDeparture = inAir.estimatedDeparture
        inAir.estimatedArrival = inAir.scheduledArrival.addingTimeInterval(14 * 60)
        inAir.phase = .enRoute
        inAir.inbound = InboundFlight(
            flightNumber: "DL 2231", originIATA: "SEA",
            scheduledArrival: inAir.scheduledDeparture.addingTimeInterval(-70 * 60),
            estimatedArrival: inAir.scheduledDeparture.addingTimeInterval(-38 * 60))
        flights.append(inAir)

        // 2) Connection leg off flight 1: JFK → LHR tonight (tight-ish).
        var connection = Flight(
            airlineName: "Delta Air Lines", airlineCode: "DL", flightNumber: "4",
            callSign: "DAL4",
            originIATA: "JFK", destinationIATA: "LHR",
            scheduledDeparture: inAir.scheduledArrival.addingTimeInterval(95 * 60),
            scheduledArrival: inAir.scheduledArrival.addingTimeInterval((95 + 415) * 60),
            departureTerminal: "4", departureGate: "A5",
            arrivalTerminal: "3", arrivalGate: "14", baggageClaim: "4",
            aircraftModel: "Airbus A330-900", registration: "N407DX")
        connection.inbound = InboundFlight(
            flightNumber: "DL 3", originIATA: "LHR",
            scheduledArrival: connection.scheduledDeparture.addingTimeInterval(-2.2 * 3600),
            estimatedArrival: connection.scheduledDeparture.addingTimeInterval(-2.0 * 3600))
        flights.append(connection)

        // 3) Tomorrow morning: ORD → AUS, on time.
        let cal = Calendar.current
        let tomorrow9 = cal.date(byAdding: .day, value: 1,
                                 to: cal.date(bySettingHour: 9, minute: 5, second: 0, of: now) ?? now) ?? now
        var tomorrow = Flight(
            airlineName: "United Airlines", airlineCode: "UA", flightNumber: "1613",
            callSign: "UAL1613",
            originIATA: "ORD", destinationIATA: "AUS",
            scheduledDeparture: tomorrow9,
            scheduledArrival: tomorrow9.addingTimeInterval(2.8 * 3600),
            departureTerminal: "1", departureGate: "B8",
            arrivalTerminal: "1", arrivalGate: "12", baggageClaim: "2",
            aircraftModel: "Boeing 737 MAX 9", registration: "N37522")
        tomorrow.inbound = InboundFlight(
            flightNumber: "UA 899", originIATA: "DEN",
            scheduledArrival: tomorrow9.addingTimeInterval(-80 * 60),
            estimatedArrival: nil)
        flights.append(tomorrow)

        // 4) Landed yesterday: LAX → SFO.
        let yesterday = now.addingTimeInterval(-26 * 3600)
        var landed = Flight(
            airlineName: "Alaska Airlines", airlineCode: "AS", flightNumber: "1042",
            callSign: "ASA1042",
            originIATA: "LAX", destinationIATA: "SFO",
            scheduledDeparture: yesterday,
            scheduledArrival: yesterday.addingTimeInterval(1.4 * 3600),
            departureTerminal: "6", departureGate: "64A",
            arrivalTerminal: "2", arrivalGate: "D5", baggageClaim: "1",
            aircraftModel: "Embraer E175", registration: "N632QX")
        landed.actualDeparture = yesterday.addingTimeInterval(6 * 60)
        landed.actualArrival = yesterday.addingTimeInterval(1.35 * 3600)
        landed.phase = .arrived
        flights.append(landed)

        return flights
    }

    // MARK: - Screenshot seed

    /// Extra past flights for the Passport / Delay Tracker store screenshots.
    /// Used ONLY by `ScreenshotMode` (see `FlightStore.seedScreenshotFlights`);
    /// never part of normal Demo Mode. IDs are fixed so seeding is idempotent.
    static func screenshotPastFlights(now: Date = .now) -> [Flight] {
        // (code, airline, number, from, to, days ago, hours, arrival delay min, aircraft, seat, cancelled)
        let rows: [(String, String, String, String, String, Int, Double, Int, String, String?, Bool)] = [
            ("DL", "Delta Air Lines", "1125", "SFO", "JFK", 296, 5.3, 0, "Boeing 767-300ER", "14A", false),
            ("UA", "United Airlines", "532", "SFO", "LAX", 262, 1.4, 0, "Boeing 737-800", nil, false),
            ("DL", "Delta Air Lines", "30", "JFK", "LHR", 231, 7.0, 0, "Airbus A330-900", "22K", false),
            ("BA", "British Airways", "304", "LHR", "CDG", 229, 1.2, 12, "Airbus A320", nil, false),
            ("AS", "Alaska Airlines", "331", "SEA", "SFO", 188, 2.1, 0, "Boeing 737-900ER", nil, false),
            ("UA", "United Airlines", "837", "SFO", "NRT", 150, 11.0, 0, "Boeing 787-9", "31A", false),
            ("DL", "Delta Air Lines", "2740", "SFO", "JFK", 112, 5.4, 120, "Airbus A321neo", nil, false),
            ("UA", "United Airlines", "1209", "AUS", "ORD", 74, 2.5, 45, "Boeing 737 MAX 9", nil, false),
            ("AS", "Alaska Airlines", "1068", "SFO", "LAX", 41, 1.4, 0, "Embraer E175", nil, true),
            ("DL", "Delta Air Lines", "415", "SFO", "JFK", 19, 5.3, 0, "Airbus A321neo", nil, false),
        ]
        let cal = Calendar.current
        return rows.enumerated().map { i, r in
            let day = cal.date(byAdding: .day, value: -r.5, to: now) ?? now
            let dep = cal.date(bySettingHour: 7 + (i * 3) % 10, minute: (i * 20) % 60, second: 0, of: day) ?? day
            var f = Flight(
                airlineName: r.1, airlineCode: r.0, flightNumber: r.2,
                callSign: nil,
                originIATA: r.3, destinationIATA: r.4,
                scheduledDeparture: dep,
                scheduledArrival: dep.addingTimeInterval(r.6 * 3600),
                departureTerminal: "1", departureGate: "B\(4 + i)",
                arrivalTerminal: "4", arrivalGate: "A\(2 + i)", baggageClaim: nil,
                aircraftModel: r.8, registration: "N\(610 + i * 7)DN")
            f.id = UUID(uuidString: String(format: "5C5C0000-0000-4000-8000-%012d", i + 1)) ?? UUID()
            f.seat = r.9
            f.isLiveData = false
            if r.10 {
                f.phase = .cancelled
            } else {
                f.actualDeparture = dep.addingTimeInterval(Double(r.7) * 60)
                f.actualArrival = f.scheduledArrival.addingTimeInterval(Double(r.7) * 60)
                f.phase = .arrived
            }
            return f
        }
    }

    // MARK: - Helpers

    /// "DL 482", "dl482", "UA1" → ("DL", "482")
    static func parseDesignator(_ raw: String) -> (code: String, number: String)? {
        let cleaned = raw.uppercased().replacingOccurrences(of: " ", with: "")
        guard cleaned.count >= 3 else { return nil }
        let letters = cleaned.prefix { $0.isLetter }
        let rest = cleaned.drop { $0.isLetter }
        guard (2...3).contains(letters.count), !rest.isEmpty, rest.allSatisfy(\.isNumber) else {
            return nil
        }
        return (String(letters), String(rest))
    }

    static func airlineName(for code: String) -> String {
        let names: [String: String] = [
            "AA": "American Airlines", "DL": "Delta Air Lines", "UA": "United Airlines",
            "WN": "Southwest Airlines", "AS": "Alaska Airlines", "B6": "JetBlue",
            "NK": "Spirit Airlines", "F9": "Frontier Airlines", "BA": "British Airways",
            "LH": "Lufthansa", "AF": "Air France", "KL": "KLM", "EK": "Emirates",
            "QR": "Qatar Airways", "SQ": "Singapore Airlines", "AC": "Air Canada",
            "VS": "Virgin Atlantic", "IB": "Iberia", "QF": "Qantas", "NH": "ANA",
            "JL": "Japan Airlines", "TK": "Turkish Airlines",
        ]
        return names[code] ?? "\(code) Airlines"
    }
}
