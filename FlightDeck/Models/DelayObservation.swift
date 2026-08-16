import Foundation

/// One completed flight's punctuality, recorded so the arrival forecaster has
/// something to reason from.
///
/// Kept separate from `Flight` on purpose. A `Flight` is a trip the user is
/// taking; an observation is a *data point* about how a route behaves, and the
/// two have different lifetimes — observations outlive the flights that
/// produced them, and can arrive from a provider backfill for flights the user
/// never took.
struct DelayObservation: Codable, Hashable, Identifiable {

    enum Source: String, Codable {
        /// The user flew it; taken from their own log.
        case flown
        /// Backfilled from the flight data provider's history.
        case provider
        /// Demo Mode: generated so the forecast UI is exercisable without a key.
        case simulated

        var isReal: Bool { self != .simulated }
    }

    /// The window the arrival forecaster reasons over. 60 days is long enough
    /// to cover a season's worth of operating pattern, short enough that a
    /// schedule change from three months ago isn't still voting.
    static let analysisWindowDays = 60

    /// Kept on disk a little longer than the analysis window, so widening the
    /// analysis later doesn't need a re-fetch.
    static let retentionDays = 120

    var id: UUID = UUID()
    var airlineCode: String
    var flightNumber: String
    var originIATA: String
    var destinationIATA: String
    var scheduledDeparture: Date
    var departureDelayMinutes: Int
    var arrivalDelayMinutes: Int
    var wasCancelled: Bool
    var source: Source
    var recordedAt: Date = .now

    // MARK: - Derived

    var designator: String { "\(airlineCode) \(flightNumber)" }
    var routeKey: String { "\(originIATA)-\(destinationIATA)" }

    /// The US DOT definition, matching `Flight.delayThresholdMinutes`.
    var isDelayed: Bool {
        !wasCancelled && arrivalDelayMinutes >= Flight.delayThresholdMinutes
    }

    /// Departure hour in the origin airport's local time. Bucketing by this
    /// matters: the same route at 07:00 and at 19:00 are different animals,
    /// because delay accumulates through the operating day.
    var departureHourLocal: Int {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = AirportDatabase.shared.airport(iata: originIATA)?.timeZone ?? .current
        return calendar.component(.hour, from: scheduledDeparture)
    }

    /// Identity for de-duplication: the same leg on the same local day should
    /// never be counted twice, however many times it gets recorded.
    var dedupKey: String {
        let day = Int(scheduledDeparture.timeIntervalSince1970 / 86_400)
        return "\(airlineCode)\(flightNumber)-\(originIATA)-\(destinationIATA)-\(day)"
    }

    // MARK: - Construction

    /// Build an observation from a completed flight — the user's own, or one
    /// pulled from the provider's history for a route they're about to fly.
    ///
    /// Returns `nil` while the flight is still in progress: an arrival delay
    /// isn't a fact until the aircraft is down.
    init?(observed flight: Flight, source: Source = .flown, at now: Date = .now) {
        guard flight.phase == .cancelled || flight.hasFlown(at: now) else { return nil }
        self.init(airlineCode: flight.airlineCode,
                  flightNumber: flight.flightNumber,
                  originIATA: flight.originIATA,
                  destinationIATA: flight.destinationIATA,
                  scheduledDeparture: flight.scheduledDeparture,
                  departureDelayMinutes: flight.departureDelayMinutes,
                  arrivalDelayMinutes: flight.arrivalDelayMinutes,
                  wasCancelled: flight.phase == .cancelled,
                  source: source)
    }

    init(id: UUID = UUID(),
         airlineCode: String,
         flightNumber: String,
         originIATA: String,
         destinationIATA: String,
         scheduledDeparture: Date,
         departureDelayMinutes: Int,
         arrivalDelayMinutes: Int,
         wasCancelled: Bool,
         source: Source,
         recordedAt: Date = .now) {
        self.id = id
        self.airlineCode = airlineCode
        self.flightNumber = flightNumber
        self.originIATA = originIATA.uppercased()
        self.destinationIATA = destinationIATA.uppercased()
        self.scheduledDeparture = scheduledDeparture
        self.departureDelayMinutes = departureDelayMinutes
        self.arrivalDelayMinutes = arrivalDelayMinutes
        self.wasCancelled = wasCancelled
        self.source = source
        self.recordedAt = recordedAt
    }
}
