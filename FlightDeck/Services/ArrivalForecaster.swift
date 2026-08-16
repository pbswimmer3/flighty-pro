import Foundation

/// A probabilistic answer to "will this land on time, and when?"
struct ArrivalForecast {

    enum Stage: Equatable {
        /// Still on the ground at the origin — the forecast is a frequency
        /// statement about how this route usually behaves.
        case beforeDeparture
        /// Airborne: the forecast is a projection of the flight actually
        /// happening, with much less room left to move.
        case inFlight
    }

    enum Confidence: Int, Comparable {
        case none = 0, low, medium, high

        var label: String {
            switch self {
            case .none: return "No history yet"
            case .low: return "Low confidence"
            case .medium: return "Medium confidence"
            case .high: return "High confidence"
            }
        }

        static func < (lhs: Confidence, rhs: Confidence) -> Bool { lhs.rawValue < rhs.rawValue }
    }

    /// One contributing piece of evidence, shown so the number is explicable
    /// rather than oracular.
    struct Factor: Identifiable, Hashable {
        var id = UUID()
        var icon: String
        var label: String
        var detail: String
        /// Minutes this factor adds to the expected arrival delay.
        var minutes: Int
        var raisesRisk: Bool
    }

    /// Probability the flight arrives 15+ minutes late (the US DOT threshold).
    var probability: Double
    /// Expected arrival delay in minutes. Negative means expected early.
    var expectedDelayMinutes: Int
    var predictedArrival: Date
    /// 20th–80th percentile arrival band.
    var earlyArrival: Date
    var lateArrival: Date

    var sampleSize: Int
    /// Plain-English description of what the number was computed from.
    var basis: String
    var confidence: Confidence
    var factors: [Factor]
    /// Share of matched historical flights that arrived on time.
    var historicalOnTimeRate: Double?
    /// True when Demo Mode's synthetic history is doing the talking.
    var usesSimulatedHistory: Bool
    var stage: Stage

    var percentText: String { "\(Int((probability * 100).rounded()))%" }

    /// Coarse risk banding, used for colour and for the one-line verdict.
    var riskLabel: String {
        switch probability {
        case ..<0.15: return "Very likely on time"
        case ..<0.30: return "Probably on time"
        case ..<0.50: return "Delay is a real risk"
        case ..<0.70: return "Delay more likely than not"
        default: return "Expect a delay"
        }
    }
}

/// Live conditions that shift a historical baseline. Assembled by the caller
/// from the same feeds `FlightIntel` already reads, so the forecast and the
/// intel signals never disagree about the facts.
struct ForecastContext {
    var inboundDelayMinutes: Int = 0
    var originEvents: [AirportEvent] = []
    var destinationEvents: [AirportEvent] = []
    var originIsIFR: Bool = false
    var destinationIsIFR: Bool = false
}

/// Turns 60 days of punctuality history plus live conditions into an arrival
/// forecast.
///
/// The model is deliberately simple and inspectable rather than a black box:
///
/// 1. **Hierarchical shrinkage** for the probability. Start from a published
///    baseline delay rate, then refine it with progressively narrower slices of
///    history — origin airport, then that airline at that airport, then the
///    route, then that airline on that route, then that time of day — each
///    pulled toward the tier below it in proportion to how little data it has.
///    Six flights on your exact route don't get to override everything, but
///    they do move the number.
/// 2. **Log-odds adjustments** for live conditions, so a ground stop can push
///    a 20% chance to 60% without ever producing an impossible probability.
/// 3. **Once the flight is airborne**, history stops guessing: the live
///    estimate becomes the centre of the distribution and the band narrows as
///    the flight progresses. History still sets the *width* — how much a
///    flight on this route typically moves after pushback.
enum ArrivalForecaster {

    /// US DOT: roughly a fifth of arrivals are 15+ minutes late in a normal
    /// year. Used as the prior when we know nothing about a route.
    static let baselineDelayRate = 0.21

    /// How many "virtual" prior flights each tier is shrunk against. Higher
    /// means history has to work harder to move the estimate.
    private static let shrinkageWeight = 5.0

    /// Spread of arrival delays assumed when history is too thin to measure it.
    private static let defaultSpreadMinutes = 22.0

    /// Typical turnaround slack that absorbs part of a late inbound aircraft
    /// before the delay reaches the passenger.
    private static let turnaroundSlackMinutes = 15.0

    // MARK: - Entry point

    /// `nil` once the flight is down or cancelled — there's nothing left to
    /// forecast.
    static func forecast(for flight: Flight,
                         history: [DelayObservation],
                         context: ForecastContext = ForecastContext(),
                         now: Date = .now) -> ArrivalForecast? {

        guard flight.phase != .cancelled, !flight.hasFlown(at: now) else { return nil }

        let matches = Matches(flight: flight, history: history)
        let sample = matches.narrowest
        let stage: ArrivalForecast.Stage = hasDeparted(flight, now: now) ? .inFlight : .beforeDeparture

        let historicalMedian = sample.map { percentile($0.sortedDelays, 0.5) } ?? 0
        let baseSpread = sample.map(spreadMinutes) ?? defaultSpreadMinutes

        // Origin-side and destination-side evidence are kept apart: once the
        // aircraft is in the air, whatever happened at the departure airport is
        // already baked into the live estimate, while the destination's
        // problems are still ahead of it.
        var originFactors: [ArrivalForecast.Factor] = []
        var destinationFactors: [ArrivalForecast.Factor] = []
        var originMinutes = 0.0
        var destinationMinutes = 0.0
        var originOdds = 0.0
        var destinationOdds = 0.0

        if context.inboundDelayMinutes >= 10 {
            let carried = max(Double(context.inboundDelayMinutes) - turnaroundSlackMinutes, 0)
            originMinutes += carried
            originOdds += min(Double(context.inboundDelayMinutes) / 25.0, 2.0)
            originFactors.append(.init(
                icon: "airplane.arrival",
                label: "Inbound aircraft \(context.inboundDelayMinutes) min late",
                detail: "Your airframe hasn't arrived yet. Around \(Int(turnaroundSlackMinutes)) min of that is usually absorbed by turnaround.",
                minutes: Int(carried.rounded()),
                raisesRisk: true))
        }

        for event in context.originEvents {
            let effect = weight(for: event, isOrigin: true)
            guard effect.minutes > 0 || effect.odds > 0 else { continue }
            originMinutes += Double(effect.minutes)
            originOdds += effect.odds
            originFactors.append(.init(
                icon: event.icon,
                label: "\(event.kind.rawValue) at \(flight.originIATA)",
                detail: effect.note,
                minutes: effect.minutes,
                raisesRisk: true))
        }

        if context.originIsIFR {
            originMinutes += 8
            originOdds += 0.35
            originFactors.append(.init(
                icon: "cloud.fog.fill",
                label: "Low visibility at \(flight.originIATA)",
                detail: "IFR conditions cut departure rates.",
                minutes: 8,
                raisesRisk: true))
        }

        for event in context.destinationEvents {
            let effect = weight(for: event, isOrigin: false)
            guard effect.minutes > 0 || effect.odds > 0 else { continue }
            destinationMinutes += Double(effect.minutes)
            destinationOdds += effect.odds
            destinationFactors.append(.init(
                icon: event.icon,
                label: "\(event.kind.rawValue) at \(flight.destinationIATA)",
                detail: effect.note,
                minutes: effect.minutes,
                raisesRisk: true))
        }

        if context.destinationIsIFR {
            destinationMinutes += 10
            destinationOdds += 0.4
            destinationFactors.append(.init(
                icon: "cloud.fog.fill",
                label: "Low visibility at \(flight.destinationIATA)",
                detail: "IFR conditions cut arrival rates and can force holding.",
                minutes: 10,
                raisesRisk: true))
        }

        var factors: [ArrivalForecast.Factor] = []
        var probability: Double
        var expectedDelay: Double
        var effectiveSpread: Double

        switch stage {
        case .beforeDeparture:
            expectedDelay = historicalMedian + originMinutes + destinationMinutes
            effectiveSpread = baseSpread
            probability = logistic(logit(shrunkProbability(matches)) + originOdds + destinationOdds)

            if let sample, sample.count >= 3 {
                factors.append(.init(
                    icon: "chart.bar.fill",
                    label: "\(sample.count) similar flights, last \(DelayObservation.analysisWindowDays) days",
                    detail: historyDetail(sample),
                    minutes: Int(historicalMedian.rounded()),
                    raisesRisk: historicalMedian >= Double(Flight.delayThresholdMinutes)))
            }
            factors.append(contentsOf: originFactors)
            factors.append(contentsOf: destinationFactors)

        case .inFlight:
            let liveDelay = Double(flight.arrivalDelayMinutes)
            let progress = flight.progress(at: now)
            // Uncertainty collapses as the flight completes; on short final
            // there is very little left to be wrong about.
            effectiveSpread = max(baseSpread * (1 - progress) * 0.8, 4)
            expectedDelay = liveDelay + destinationMinutes
            probability = 1 - normalCDF((Double(Flight.delayThresholdMinutes) - expectedDelay) / effectiveSpread)

            factors.append(.init(
                icon: "airplane",
                label: liveDelay >= Double(Flight.delayThresholdMinutes)
                    ? "Running \(Int(liveDelay.rounded())) min behind"
                    : "Tracking to schedule",
                detail: "Live estimate, \(Int((progress * 100).rounded()))% of the way there.",
                minutes: Int(liveDelay.rounded()),
                raisesRisk: liveDelay >= Double(Flight.delayThresholdMinutes)))
            factors.append(contentsOf: destinationFactors)
        }

        probability = min(max(probability, 0.01), 0.99)

        let predicted = flight.scheduledArrival.addingTimeInterval(expectedDelay * 60)
        // ±0.8416σ spans the 20th–80th percentile of a normal distribution.
        let band = 0.8416 * effectiveSpread * 60

        return ArrivalForecast(
            probability: probability,
            expectedDelayMinutes: Int(expectedDelay.rounded()),
            predictedArrival: predicted,
            earlyArrival: predicted.addingTimeInterval(-band),
            lateArrival: predicted.addingTimeInterval(band),
            sampleSize: sample?.count ?? 0,
            basis: basisText(matches, stage: stage),
            confidence: confidence(for: sample?.count ?? 0, stage: stage),
            factors: factors,
            historicalOnTimeRate: sample.map { 1 - $0.delayRate },
            usesSimulatedHistory: sample?.hasSimulatedData ?? false,
            stage: stage)
    }

    private static func hasDeparted(_ flight: Flight, now: Date) -> Bool {
        if flight.actualDeparture != nil { return true }
        return flight.effectivePhase.isAirborne
    }

    /// What a live airport program contributes, in minutes and log-odds.
    private struct Effect {
        var minutes: Int
        var odds: Double
        var note: String
    }

    private static func weight(for event: AirportEvent, isOrigin: Bool) -> Effect {
        switch event.kind {
        case .closure:
            return Effect(minutes: 60, odds: 1.6, note: isOrigin
                          ? "The field is closed — departures are not moving."
                          : "The destination is closed; holding or diversion is possible.")
        case .groundStop:
            return Effect(minutes: 35, odds: 1.2, note: isOrigin
                          ? "Departures are being held on the ground."
                          : "Flights to this airport are held at their origin.")
        case .groundDelay:
            return Effect(minutes: 22, odds: 0.8, note: "Traffic into the airport is being metered.")
        case .departureDelay:
            return isOrigin
                ? Effect(minutes: 18, odds: 0.7, note: "Departures are running behind.")
                : Effect(minutes: 0, odds: 0, note: "")
        case .arrivalDelay:
            return isOrigin
                ? Effect(minutes: 0, odds: 0, note: "")
                : Effect(minutes: 15, odds: 0.6, note: "Arrivals are running behind.")
        }
    }

    // MARK: - Matching history

    /// A slice of history and the summary statistics that fall out of it.
    struct Sample {
        var observations: [DelayObservation]
        var label: String

        var count: Int { observations.count }

        var delayRate: Double {
            guard !observations.isEmpty else { return ArrivalForecaster.baselineDelayRate }
            return Double(observations.filter(\.isDelayed).count) / Double(observations.count)
        }

        var sortedDelays: [Double] {
            observations.map { Double($0.arrivalDelayMinutes) }.sorted()
        }

        var hasSimulatedData: Bool {
            observations.contains(where: { $0.source == .simulated })
        }
    }

    /// The tier ladder, broadest first. Each tier is a subset of an earlier
    /// one, which is what makes the shrinkage chain meaningful.
    struct Matches {
        var tiers: [Sample] = []

        init(flight: Flight, history: [DelayObservation]) {
            let origin = flight.originIATA.uppercased()
            let destination = flight.destinationIATA.uppercased()
            let airline = flight.airlineCode.uppercased()
            let hour = flight.departureHourLocal

            let fromOrigin = history.filter { $0.originIATA == origin }
            let airlineAtOrigin = fromOrigin.filter { $0.airlineCode.uppercased() == airline }
            let route = history.filter { $0.originIATA == origin && $0.destinationIATA == destination }
            let airlineOnRoute = route.filter { $0.airlineCode.uppercased() == airline }
            let sameTimeOfDay = airlineOnRoute.filter {
                Self.hourDistance($0.departureHourLocal, hour) <= 3
            }

            tiers = [
                Sample(observations: fromOrigin, label: "departures from \(origin)"),
                Sample(observations: airlineAtOrigin, label: "\(airline) departures from \(origin)"),
                Sample(observations: route, label: "\(origin)→\(destination) flights"),
                Sample(observations: airlineOnRoute, label: "\(airline) flights on \(origin)→\(destination)"),
                Sample(observations: sameTimeOfDay,
                       label: "\(airline) flights on \(origin)→\(destination) near \(hour):00"),
            ].filter { !$0.observations.isEmpty }
        }

        /// The most specific tier that still has enough data to say something,
        /// falling back to the narrowest tier we have at all.
        var narrowest: Sample? {
            tiers.last { $0.count >= 3 } ?? tiers.last
        }

        /// Distance between two clock hours, the short way round midnight.
        private static func hourDistance(_ a: Int, _ b: Int) -> Int {
            let raw = abs(a - b) % 24
            return min(raw, 24 - raw)
        }
    }

    /// Walk the ladder from the global prior upward, each tier shrunk toward
    /// the estimate below it.
    private static func shrunkProbability(_ matches: Matches) -> Double {
        var estimate = baselineDelayRate
        for tier in matches.tiers {
            let delayed = Double(tier.observations.filter(\.isDelayed).count)
            let n = Double(tier.count)
            estimate = (delayed + shrinkageWeight * estimate) / (n + shrinkageWeight)
        }
        return estimate
    }

    private static func spreadMinutes(_ sample: Sample) -> Double {
        guard sample.count >= 4 else { return defaultSpreadMinutes }
        let sorted = sample.sortedDelays
        // Interquartile range over 1.349 is a robust σ — one four-hour ATC
        // meltdown shouldn't triple the width of every future forecast.
        let sigma = (percentile(sorted, 0.75) - percentile(sorted, 0.25)) / 1.349
        return min(max(sigma, 6), 90)
    }

    private static func confidence(for sampleSize: Int,
                                   stage: ArrivalForecast.Stage) -> ArrivalForecast.Confidence {
        if stage == .inFlight { return sampleSize >= 5 ? .high : .medium }
        switch sampleSize {
        case 0: return .none
        case 1..<5: return .low
        case 5..<15: return .medium
        default: return .high
        }
    }

    private static func historyDetail(_ sample: Sample) -> String {
        let onTime = Int(((1 - sample.delayRate) * 100).rounded())
        let median = Int(percentile(sample.sortedDelays, 0.5).rounded())
        let medianText = median <= 0 ? "\(abs(median)) min early" : "\(median) min late"
        return "\(onTime)% arrived on time; typical arrival \(medianText)."
    }

    private static func basisText(_ matches: Matches, stage: ArrivalForecast.Stage) -> String {
        guard let sample = matches.narrowest, sample.count > 0 else {
            return stage == .inFlight
                ? "Live position and the airline's current estimate."
                : "No matching history yet — showing the industry baseline until this route builds a record."
        }
        let base = "\(sample.count) \(sample.label) in the last \(DelayObservation.analysisWindowDays) days"
        return stage == .inFlight ? "\(base), plus the live estimate." : "\(base)."
    }

    // MARK: - Math

    /// Linear-interpolated percentile of an already-sorted array.
    static func percentile(_ sorted: [Double], _ p: Double) -> Double {
        guard !sorted.isEmpty else { return 0 }
        guard sorted.count > 1 else { return sorted[0] }
        let rank = min(max(p, 0), 1) * Double(sorted.count - 1)
        let lower = Int(rank.rounded(.down))
        let upper = min(lower + 1, sorted.count - 1)
        let fraction = rank - Double(lower)
        return sorted[lower] + (sorted[upper] - sorted[lower]) * fraction
    }

    static func logit(_ p: Double) -> Double {
        let clamped = min(max(p, 0.001), 0.999)
        return log(clamped / (1 - clamped))
    }

    static func logistic(_ x: Double) -> Double { 1 / (1 + exp(-x)) }

    /// Standard normal CDF, Abramowitz & Stegun 26.2.17 (|error| < 7.5e-8).
    /// Hand-rolled rather than pulled from a numerics package so the app stays
    /// dependency-free.
    static func normalCDF(_ z: Double) -> Double {
        let b1 = 0.319381530, b2 = -0.356563782, b3 = 1.781477937
        let b4 = -1.821255978, b5 = 1.330274429, p = 0.2316419
        let absZ = abs(z)
        let t = 1.0 / (1.0 + p * absZ)
        let density = exp(-absZ * absZ / 2) / (2 * Double.pi).squareRoot()
        let poly = t * (b1 + t * (b2 + t * (b3 + t * (b4 + t * b5))))
        let tail = density * poly
        return z >= 0 ? 1 - tail : tail
    }
}
