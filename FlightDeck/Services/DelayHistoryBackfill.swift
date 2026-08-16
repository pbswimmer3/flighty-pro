import Foundation

/// Fills the punctuality record for a route the user is about to fly.
///
/// A personal flight log is sparse by definition — you might fly SFO→JFK three
/// times a year, which is nowhere near enough to say "23% chance of delay".
/// So the forecast leans on two other sources:
///
/// * **Provider history** when a real API key is configured: the same flight
///   number on recent past dates, sampled rather than fetched day by day so a
///   forecast costs a dozen calls instead of sixty.
/// * **Deterministic synthetic history** in Demo Mode, clearly marked as
///   `.simulated` everywhere it surfaces, so the whole feature is exercisable
///   without a key — and never mistakable for real data.
struct DelayHistoryBackfill {

    let provider: FlightDataProvider
    let isDemo: Bool

    /// Past dates sampled when scanning a real provider: every third day for
    /// six weeks. Enough spread to catch a weekly pattern, cheap enough to run
    /// when a flight page opens.
    private static let providerSampleDays = Array(stride(from: 2, through: 44, by: 3))

    /// Pause between provider calls. RapidAPI free tiers rate-limit hard, and
    /// this is background work — nothing on screen is waiting for it.
    private static let pauseBetweenCalls: Duration = .milliseconds(350)

    // MARK: - Entry point

    func observations(for flight: Flight, now: Date = .now) async -> [DelayObservation] {
        isDemo
            ? Self.simulatedHistory(for: flight, now: now)
            : await providerHistory(for: flight, now: now)
    }

    // MARK: - Real history

    /// Deliberately sequential. Fifteen simultaneous requests is a good way to
    /// get a 429 and learn nothing; the user isn't blocked on this either way.
    private func providerHistory(for flight: Flight, now: Date = .now) async -> [DelayObservation] {
        let calendar = Calendar.current
        let designator = "\(flight.airlineCode)\(flight.flightNumber)"
        var collected: [DelayObservation] = []

        for offset in Self.providerSampleDays {
            if Task.isCancelled { break }
            guard let date = calendar.date(byAdding: .day, value: -offset, to: now) else { continue }
            guard let results = try? await provider.searchFlights(number: designator, date: date) else {
                continue
            }
            // A designator can fly several segments a day; only the one that
            // walks the same route tells us anything about this flight.
            collected += results
                .filter { $0.originIATA == flight.originIATA
                          && $0.destinationIATA == flight.destinationIATA }
                .compactMap { DelayObservation(observed: $0, source: .provider, at: now) }

            try? await Task.sleep(for: Self.pauseBetweenCalls)
        }
        return collected
    }

    // MARK: - Demo history

    /// Synthetic but *stable*: the same route always produces the same history,
    /// so the forecast doesn't jitter every time the screen is reopened.
    ///
    /// Three tiers are generated so the forecaster's shrinkage ladder has
    /// something to climb: this airline on this route, other airlines on the
    /// same route, and this airline out of the same origin.
    static func simulatedHistory(for flight: Flight, now: Date = .now) -> [DelayObservation] {
        var generator = SeededGenerator(seed: stableSeed(
            "\(flight.airlineCode)|\(flight.originIATA)|\(flight.destinationIATA)"))

        // Each route gets its own punctuality personality, held steady across
        // launches by the seed.
        let onTimeRate = Double.random(in: 0.58...0.88, using: &generator)
        let meanDelayWhenLate = Double.random(in: 22...75, using: &generator)

        var observations: [DelayObservation] = []

        observations += leg(count: 24,
                            airline: flight.airlineCode,
                            number: flight.flightNumber,
                            origin: flight.originIATA,
                            destination: flight.destinationIATA,
                            referenceDeparture: flight.scheduledDeparture,
                            onTimeRate: onTimeRate,
                            meanDelayWhenLate: meanDelayWhenLate,
                            now: now,
                            generator: &generator)

        for (index, code) in otherAirlines(excluding: flight.airlineCode).enumerated() {
            observations += leg(count: 9,
                                airline: code,
                                number: String(100 + index * 37),
                                origin: flight.originIATA,
                                destination: flight.destinationIATA,
                                referenceDeparture: flight.scheduledDeparture
                                    .addingTimeInterval(Double(index - 1) * 3 * 3600),
                                onTimeRate: max(onTimeRate - 0.08, 0.4),
                                meanDelayWhenLate: meanDelayWhenLate + 6,
                                now: now,
                                generator: &generator)
        }

        for (index, destination) in otherDestinations(from: flight.originIATA,
                                                      excluding: flight.destinationIATA).enumerated() {
            observations += leg(count: 8,
                                airline: flight.airlineCode,
                                number: String(600 + index * 13),
                                origin: flight.originIATA,
                                destination: destination,
                                referenceDeparture: flight.scheduledDeparture
                                    .addingTimeInterval(Double(index) * 2 * 3600),
                                onTimeRate: onTimeRate + 0.03,
                                meanDelayWhenLate: meanDelayWhenLate - 4,
                                now: now,
                                generator: &generator)
        }

        return observations
    }

    /// One synthetic leg's worth of history, spread back across the window.
    private static func leg(count: Int,
                            airline: String,
                            number: String,
                            origin: String,
                            destination: String,
                            referenceDeparture: Date,
                            onTimeRate: Double,
                            meanDelayWhenLate: Double,
                            now: Date,
                            generator: inout SeededGenerator) -> [DelayObservation] {

        let window = Double(DelayObservation.analysisWindowDays)
        let spacing = window / Double(max(count, 1))
        var results: [DelayObservation] = []

        for index in 0..<count {
            // Walk backwards from yesterday, jittered so the samples don't fall
            // on a perfectly regular cadence.
            let daysBack = Double(index) * spacing + Double.random(in: 0...spacing * 0.6, using: &generator) + 1
            guard daysBack <= window else { continue }

            // Keep the time-of-day of the reference flight so the forecaster's
            // "same time of day" tier has something to match on.
            let departure = referenceDeparture.addingTimeInterval(-daysBack * 86_400)
            guard departure < now else { continue }

            let roll = Double.random(in: 0...1, using: &generator)
            var arrivalDelay: Int
            var wasCancelled = false

            if roll < 0.015 {
                wasCancelled = true
                arrivalDelay = 0
            } else if roll < onTimeRate {
                // On-time flights cluster slightly early — airlines pad blocks.
                arrivalDelay = Int(Double.random(in: -18 ... 14, using: &generator).rounded())
            } else {
                // Delays are long-tailed: an exponential draw around the mean.
                let uniform = Double.random(in: 0.02...0.98, using: &generator)
                arrivalDelay = Int((meanDelayWhenLate * -log(uniform)).rounded())
                arrivalDelay = min(max(arrivalDelay, Flight.delayThresholdMinutes), 300)
            }

            // Departure delay tracks arrival delay but with some recovery in
            // the air, which is how real operations behave.
            let recovery = Double.random(in: 0...12, using: &generator)
            let departureDelay = wasCancelled ? 0 : Int(max(Double(arrivalDelay) + recovery, -20).rounded())

            results.append(DelayObservation(
                airlineCode: airline,
                flightNumber: number,
                originIATA: origin,
                destinationIATA: destination,
                scheduledDeparture: departure,
                departureDelayMinutes: departureDelay,
                arrivalDelayMinutes: arrivalDelay,
                wasCancelled: wasCancelled,
                source: .simulated,
                recordedAt: now))
        }
        return results
    }

    private static func otherAirlines(excluding code: String) -> [String] {
        ["AA", "DL", "UA", "AS", "B6"].filter { $0 != code.uppercased() }.prefix(3).map { $0 }
    }

    private static func otherDestinations(from origin: String, excluding destination: String) -> [String] {
        ["LAX", "ORD", "DEN", "ATL", "SEA", "JFK"]
            .filter { $0 != origin.uppercased() && $0 != destination.uppercased() }
            .prefix(3)
            .map { $0 }
    }

    /// FNV-1a. `String.hashValue` is seeded per process, so it would give this
    /// route a different personality on every launch.
    static func stableSeed(_ string: String) -> UInt64 {
        var hash: UInt64 = 0xcbf29ce484222325
        for byte in string.utf8 {
            hash ^= UInt64(byte)
            hash = hash &* 0x100000001b3
        }
        return hash
    }
}

/// SplitMix64 — small, fast, and reproducible from a seed.
struct SeededGenerator: RandomNumberGenerator {
    private var state: UInt64

    init(seed: UInt64) { state = seed }

    mutating func next() -> UInt64 {
        state = state &+ 0x9E3779B97F4A7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58476D1CE4E5B9
        z = (z ^ (z >> 27)) &* 0x94D049BB133111EB
        return z ^ (z >> 31)
    }
}
