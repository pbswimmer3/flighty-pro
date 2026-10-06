import Foundation

/// Everything the Passport screen shows, computed in one pass over the user's
/// flight log.
///
/// Deliberately a value type with a pure builder: the Passport is a *view* of
/// `FlightStore.flights`, never a second copy of the truth. Recomputing costs
/// microseconds for a realistic log (hundreds of flights), and nothing can
/// drift out of sync with the flights themselves.
struct PassportStats {

    // MARK: - Scope

    enum Scope: Hashable, Identifiable {
        case allTime
        case year(Int)

        var id: String {
            switch self {
            case .allTime: return "all"
            case .year(let y): return String(y)
            }
        }

        var label: String {
            switch self {
            case .allTime: return "All Time"
            case .year(let y): return String(y)
            }
        }
    }

    // MARK: - Nested tallies

    /// A ranked "you flew this N times" row — airlines, airports, aircraft,
    /// tail numbers and seats all share the shape.
    struct Tally: Identifiable, Hashable {
        var key: String
        var label: String
        var detail: String?
        var count: Int

        var id: String { key }
    }

    struct RouteTally: Identifiable, Hashable {
        var origin: String
        var destination: String
        var count: Int
        var miles: Double

        var id: String { "\(origin)-\(destination)" }
        var label: String { "\(origin) ⇄ \(destination)" }

        /// City pairs are direction-agnostic here: SFO→JFK and JFK→SFO are the
        /// same route flown twice, which is how people actually think about it.
        static func pairKey(_ a: String, _ b: String) -> String {
            a <= b ? "\(a)-\(b)" : "\(b)-\(a)"
        }
    }

    /// One notable delay, kept with enough context to render a row.
    struct DelayRecord: Identifiable, Hashable {
        var flightID: UUID
        var designator: String
        var route: String
        var date: Date
        var minutes: Int

        var id: UUID { flightID }
    }

    /// The delay tracker: how often, how badly, and who did it to you.
    struct DelayStats: Equatable {
        var flightsCounted = 0
        var delayedFlights = 0
        var cancelledFlights = 0
        /// Sum of arrival delay across the flights that *count* as delayed —
        /// i.e. only those past the 15-minute DOT threshold, not every flight
        /// that landed a minute or two late.
        ///
        /// It has to be scoped that way for `averageDelayMinutes` below to mean
        /// anything: that divides by `delayedFlights`, so summing every
        /// small positive delay into the numerator would inflate "when it goes
        /// wrong, this is how wrong" with flights that never went wrong.
        var totalDelayMinutes = 0
        var worst: DelayRecord?
        /// Airlines ranked by delayed-flight count, with their rate in `detail`.
        var byAirline: [Tally] = []
        /// Airports ranked by delayed *arrivals* into them.
        var byAirport: [Tally] = []
        var recent: [DelayRecord] = []

        var onTimeFlights: Int { max(flightsCounted - delayedFlights, 0) }

        var onTimeRate: Double {
            flightsCounted == 0 ? 0 : Double(onTimeFlights) / Double(flightsCounted)
        }

        var delayRate: Double {
            flightsCounted == 0 ? 0 : Double(delayedFlights) / Double(flightsCounted)
        }

        var totalDelayInterval: TimeInterval { TimeInterval(totalDelayMinutes) * 60 }

        /// Averaged over delayed flights, not all flights — "when it goes
        /// wrong, this is how wrong" is the useful number.
        var averageDelayMinutes: Int {
            delayedFlights == 0 ? 0 : Int((Double(totalDelayMinutes) / Double(delayedFlights)).rounded())
        }
    }

    // MARK: - Headline

    var scope: Scope = .allTime

    /// The flown flights in scope, newest first. Drives the Past Flights list
    /// and the Passport map.
    var flights: [Flight] = []

    var flightCount = 0
    var totalMiles: Double = 0
    var totalAirTime: TimeInterval = 0

    var airports: [Tally] = []
    var airlines: [Tally] = []
    var aircraft: [Tally] = []
    var airframes: [Tally] = []       // by tail number
    var seats: [Tally] = []
    var routes: [RouteTally] = []
    var countries: [Tally] = []

    var delays = DelayStats()

    var longestFlight: Flight?
    var shortestFlight: Flight?

    var domesticCount = 0
    var internationalCount = 0
    var longHaulCount = 0
    var redEyeCount = 0

    /// Indexed 0…6 for Sunday…Saturday.
    var weekdayHistogram: [Int] = Array(repeating: 0, count: 7)

    /// Airports we couldn't resolve in the bundled database. Their mileage is
    /// missing from `totalMiles`, and the UI says so rather than pretending.
    var unresolvedAirports: [String] = []

    /// Years present in the log, newest first — the Passport's scope picker.
    var availableYears: [Int] = []

    // MARK: - Derived headline numbers

    static let earthCircumferenceMiles = 24_901.0
    static let distanceToMoonMiles = 238_855.0

    var timesAroundTheWorld: Double { totalMiles / Self.earthCircumferenceMiles }
    var fractionOfWayToTheMoon: Double { totalMiles / Self.distanceToMoonMiles }

    var isEmpty: Bool { flightCount == 0 && delays.cancelledFlights == 0 }

    var mostFlownAircraft: Tally? { aircraft.first }
    var mostFlownAirline: Tally? { airlines.first }
    var mostVisitedAirport: Tally? { airports.first }
    var mostFlownRoute: RouteTally? { routes.first }

    var averageFlightLength: TimeInterval {
        flightCount == 0 ? 0 : totalAirTime / Double(flightCount)
    }
}

// MARK: - Builder

extension PassportStats {

    /// Fold the whole flight log into one Passport.
    ///
    /// `flights` is the complete log; scoping and the flown/cancelled split
    /// happen here so a year view still knows about that year's cancellations.
    static func build(from flights: [Flight],
                      scope: Scope = .allTime,
                      now: Date = .now) -> PassportStats {

        var stats = PassportStats()
        stats.scope = scope
        stats.availableYears = Set(flights.map(\.departureYear)).sorted(by: >)

        let inScope = flights.filter { flight in
            switch scope {
            case .allTime: return true
            case .year(let year): return flight.departureYear == year
            }
        }

        stats.delays.cancelledFlights = inScope.filter { $0.phase == .cancelled }.count

        let flown = inScope
            .filter { $0.hasFlown(at: now) }
            .sorted { $0.bestDeparture > $1.bestDeparture }

        stats.flights = flown
        stats.flightCount = flown.count

        guard !flown.isEmpty else { return stats }

        // Accumulators — one pass, then rank at the end.
        var airportCounts: [String: Int] = [:]
        var airlineCounts: [String: Int] = [:]
        var airlineNames: [String: String] = [:]
        var aircraftCounts: [String: Int] = [:]
        var airframeCounts: [String: Int] = [:]
        var airframeTypes: [String: String] = [:]
        var seatCounts: [String: Int] = [:]
        var countryCounts: [String: Int] = [:]
        var routeCounts: [String: (origin: String, destination: String, count: Int, miles: Double)] = [:]
        var airlineDelays: [String: DelayAccumulator] = [:]
        var airportDelays: [String: DelayAccumulator] = [:]
        var unresolved: Set<String> = []
        var delayRecords: [DelayRecord] = []

        for flight in flown {
            // Distance & time
            if let miles = flight.routeDistanceMiles {
                stats.totalMiles += miles
            } else {
                if flight.originAirport == nil { unresolved.insert(flight.originIATA) }
                if flight.destinationAirport == nil { unresolved.insert(flight.destinationIATA) }
            }
            stats.totalAirTime += max(flight.duration, 0)

            // Airports (both ends count as a visit)
            airportCounts[flight.originIATA, default: 0] += 1
            airportCounts[flight.destinationIATA, default: 0] += 1

            // Airlines
            airlineCounts[flight.airlineCode, default: 0] += 1
            airlineNames[flight.airlineCode] = flight.airlineName

            // Aircraft type & specific airframe
            if let type = flight.aircraftType {
                aircraftCounts[type, default: 0] += 1
            }
            if let tail = flight.tailNumber {
                airframeCounts[tail, default: 0] += 1
                if let type = flight.aircraftType { airframeTypes[tail] = type }
            }

            // Seat
            if let seat = flight.seat?.trimmingCharacters(in: .whitespacesAndNewlines).uppercased(),
               !seat.isEmpty {
                seatCounts[seat, default: 0] += 1
            }

            // Countries
            for airport in [flight.originAirport, flight.destinationAirport].compactMap({ $0 }) {
                countryCounts[airport.country, default: 0] += 1
            }

            // Routes (direction-agnostic)
            let key = RouteTally.pairKey(flight.originIATA, flight.destinationIATA)
            let miles = flight.routeDistanceMiles ?? 0
            if var existing = routeCounts[key] {
                existing.count += 1
                existing.miles += miles
                routeCounts[key] = existing
            } else {
                // Store the first direction seen so the label is stable.
                routeCounts[key] = (flight.originIATA, flight.destinationIATA, 1, miles)
            }

            // Shape of the trip
            if flight.isInternational { stats.internationalCount += 1 } else { stats.domesticCount += 1 }
            if flight.isLongHaul { stats.longHaulCount += 1 }
            if flight.isRedEye { stats.redEyeCount += 1 }

            let weekdayIndex = min(max(flight.departureWeekday - 1, 0), 6)
            stats.weekdayHistogram[weekdayIndex] += 1

            // Delay tracking
            stats.delays.flightsCounted += 1
            airlineDelays[flight.airlineCode, default: DelayAccumulator()].flights += 1
            airportDelays[flight.destinationIATA, default: DelayAccumulator()].flights += 1

            if flight.isDelayedByDOT {
                let minutes = flight.arrivalDelayMinutes
                stats.delays.delayedFlights += 1
                stats.delays.totalDelayMinutes += minutes
                airlineDelays[flight.airlineCode, default: DelayAccumulator()].delayed += 1
                airlineDelays[flight.airlineCode, default: DelayAccumulator()].minutes += minutes
                airportDelays[flight.destinationIATA, default: DelayAccumulator()].delayed += 1

                delayRecords.append(DelayRecord(
                    flightID: flight.id,
                    designator: flight.displayNumber,
                    route: "\(flight.originIATA) → \(flight.destinationIATA)",
                    date: flight.bestDeparture,
                    minutes: minutes))
            }

            // Superlatives
            if stats.longestFlight == nil || flight.duration > (stats.longestFlight?.duration ?? 0) {
                stats.longestFlight = flight
            }
            if stats.shortestFlight == nil || flight.duration < (stats.shortestFlight?.duration ?? .infinity) {
                stats.shortestFlight = flight
            }
        }

        stats.unresolvedAirports = unresolved.sorted()

        stats.airports = rank(airportCounts) { code, count in
            Tally(key: code,
                  label: code,
                  detail: AirportDatabase.shared.airport(iata: code)?.city,
                  count: count)
        }

        stats.airlines = rank(airlineCounts) { code, count in
            Tally(key: code, label: airlineNames[code] ?? code, detail: code, count: count)
        }

        stats.aircraft = rank(aircraftCounts) { type, count in
            Tally(key: type, label: type, detail: nil, count: count)
        }

        stats.airframes = rank(airframeCounts) { tail, count in
            Tally(key: tail, label: tail, detail: airframeTypes[tail], count: count)
        }

        stats.seats = rank(seatCounts) { seat, count in
            Tally(key: seat, label: seat, detail: nil, count: count)
        }

        stats.countries = rank(countryCounts) { country, count in
            Tally(key: country, label: country, detail: nil, count: count)
        }

        stats.routes = routeCounts
            .map { RouteTally(origin: $0.value.origin,
                              destination: $0.value.destination,
                              count: $0.value.count,
                              miles: $0.value.miles) }
            .sorted { ($0.count, $0.miles) > ($1.count, $1.miles) }

        stats.delays.byAirline = rankTallies(airlineDelays
            .filter { $0.value.delayed > 0 }
            .map { code, value in
                Tally(key: code,
                      label: airlineNames[code] ?? code,
                      detail: "\(value.ratePercent)% of \(value.flights) · \(value.minutes) min lost",
                      count: value.delayed)
            })

        stats.delays.byAirport = rankTallies(airportDelays
            .filter { $0.value.delayed > 0 }
            .map { code, value in
                Tally(key: code,
                      label: code,
                      detail: "\(value.delayed) of \(value.flights) arrivals · \(value.ratePercent)%",
                      count: value.delayed)
            })

        stats.delays.worst = delayRecords.max { $0.minutes < $1.minutes }
        stats.delays.recent = delayRecords.sorted { $0.date > $1.date }

        return stats
    }

    /// Running totals while folding the log. A named type rather than a tuple
    /// so `[String: …]` subscripting with a default stays readable.
    private struct DelayAccumulator {
        var flights = 0
        var delayed = 0
        var minutes = 0

        var ratePercent: Int {
            flights == 0 ? 0 : Int((Double(delayed) / Double(flights) * 100).rounded())
        }
    }

    /// Highest count first, ties broken alphabetically so the order doesn't
    /// shuffle between rebuilds of identical data.
    private static func rank(_ counts: [String: Int],
                             _ transform: (String, Int) -> Tally) -> [Tally] {
        rankTallies(counts.map { transform($0.key, $0.value) })
    }

    private static func rankTallies(_ tallies: [Tally]) -> [Tally] {
        tallies.sorted { lhs, rhs in
            lhs.count == rhs.count ? lhs.key < rhs.key : lhs.count > rhs.count
        }
    }
}
