import Foundation
import Combine

/// Source of truth for the user's tracked flights. Persists to a JSON file in
/// Application Support and periodically refreshes active flights.
@MainActor
final class FlightStore: ObservableObject {
    @Published private(set) var flights: [Flight] = []
    @Published var lastRefresh: Date?

    /// Advanced on a timer purely so time-based sectioning re-renders. Without
    /// it a flight that crosses its archive threshold while the app sits open
    /// would stay in Today until something else happened to publish a change.
    @Published private(set) var clock: Date = .now

    private let settings: SettingsStore
    private let history: DelayHistoryStore
    private var refreshTimer: Timer?
    private var clockTimer: Timer?

    init(settings: SettingsStore, history: DelayHistoryStore) {
        self.settings = settings
        self.history = history
        load()
        if flights.isEmpty && settings.demoMode {
            flights = DemoFlightProvider.sampleFlights()
            save()
        }
        recordCompletedFlights()

        // Re-evaluate live flights every 90 seconds while the app is open.
        refreshTimer = Timer.scheduledTimer(withTimeInterval: 90, repeats: true) { [weak self] _ in
            Task { @MainActor in await self?.refreshActive() }
        }
        // Half-minute resolution on the "30 minutes after landing" rule is
        // plenty, and costs nothing.
        clockTimer = Timer.scheduledTimer(withTimeInterval: 30, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.tick() }
        }
    }

    deinit {
        refreshTimer?.invalidate()
        clockTimer?.invalidate()
    }

    /// Publish a new instant and sweep any flight that just finished into the
    /// punctuality record.
    private func tick() {
        clock = .now
        recordCompletedFlights()
    }

    // MARK: - Mutations

    func add(_ flight: Flight) {
        guard !flights.contains(where: { $0.id == flight.id }) else { return }
        flights.append(flight)
        sort()
        save()
    }

    func remove(_ flight: Flight) {
        flights.removeAll { $0.id == flight.id }
        save()
    }

    /// Replace a flight in place — used for user-supplied details the provider
    /// can't know, like the seat.
    func update(_ flight: Flight) {
        guard let idx = flights.firstIndex(where: { $0.id == flight.id }) else { return }
        flights[idx] = flight
        save()
    }

    func setSeat(_ seat: String?, for flight: Flight) {
        guard var updated = flights.first(where: { $0.id == flight.id }) else { return }
        let trimmed = seat?.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        updated.seat = (trimmed?.isEmpty ?? true) ? nil : trimmed
        update(updated)
    }

    func addSampleTrip() {
        for f in DemoFlightProvider.sampleFlights() {
            // Skip duplicates by designator + origin.
            if !flights.contains(where: { $0.displayNumber == f.displayNumber && $0.originIATA == f.originIATA }) {
                flights.append(f)
            }
        }
        sort()
        save()
    }

    func clearAll() {
        flights.removeAll()
        save()
    }

    // MARK: - Refresh

    /// Refresh every flight that's in its live window.
    func refreshActive() async {
        let provider = settings.provider
        var changed = false
        for (idx, flight) in flights.enumerated() where flight.isActive {
            if let updated = try? await provider.refresh(flight: flight) {
                flights[idx] = updated
                changed = true
            }
        }
        lastRefresh = .now
        if changed { sort(); save() }
    }

    func refresh(_ flight: Flight) async {
        guard let idx = flights.firstIndex(where: { $0.id == flight.id }) else { return }
        if let updated = try? await settings.provider.refresh(flight: flight) {
            flights[idx] = updated
            save()
        }
    }

    // MARK: - Sections for the list UI

    /// Everything still ahead of the user or in the air — the live list.
    ///
    /// The dividing line is landing plus 30 minutes, not the calendar day: a
    /// red-eye that touches down at 06:00 shouldn't vanish at midnight while
    /// it's still in the air, and a flight that landed an hour ago shouldn't
    /// still be sitting at the top of the screen.
    var activeFlights: [Flight] {
        flights.filter { !$0.isArchived(at: clock) }
    }

    var todayFlights: [Flight] {
        activeFlights.filter {
            Calendar.current.isDateInToday($0.scheduledDeparture) || $0.effectivePhase.isAirborne
        }
    }

    var upcomingFlights: [Flight] {
        activeFlights.filter {
            !Calendar.current.isDateInToday($0.scheduledDeparture)
                && $0.scheduledDeparture > clock
                && !$0.effectivePhase.isAirborne
        }
    }

    /// Archived flights, newest first. A flight lands here automatically 30
    /// minutes after arrival — see `Flight.archivesAt`.
    var pastFlights: [Flight] {
        flights
            .filter { $0.isArchived(at: clock) }
            .sorted { $0.bestDeparture > $1.bestDeparture }
    }

    /// The next flight to leave, if any — the headline of the Flights tab.
    var nextFlight: Flight? {
        activeFlights
            .filter { !$0.effectivePhase.isComplete }
            .min { $0.bestDeparture < $1.bestDeparture }
    }

    // MARK: - Passport

    func passport(scope: PassportStats.Scope = .allTime) -> PassportStats {
        PassportStats.build(from: flights, scope: scope, now: clock)
    }

    // MARK: - Punctuality record

    /// Fold every finished flight into the delay history. Idempotent: the
    /// history store de-duplicates by leg and day.
    private func recordCompletedFlights(at now: Date = .now) {
        let finished = flights.filter { $0.phase == .cancelled || $0.hasFlown(at: now) }
        guard !finished.isEmpty else { return }
        let observations = finished.compactMap {
            DelayObservation(observed: $0, source: .flown, at: now)
        }
        history.ingest(observations)
    }

    // MARK: - Connection detection

    /// Flight pairs that look like connections: leg 1 arrives where leg 2
    /// departs, within the gap window in `ConnectionRules`. The upper bound
    /// matters — without it an overnight stay in a city reads as a layover.
    var detectedConnections: [(inbound: Flight, outbound: Flight)] {
        var pairs: [(Flight, Flight)] = []
        let minGap = TimeInterval(ConnectionRules.minGapMinutes * 60)
        let maxGap = TimeInterval(ConnectionRules.maxConnectionMinutes * 60)
        let sorted = flights.sorted { $0.scheduledDeparture < $1.scheduledDeparture }
        for (i, a) in sorted.enumerated() {
            for b in sorted.dropFirst(i + 1) {
                let gap = b.scheduledDeparture.timeIntervalSince(a.scheduledArrival)
                if a.destinationIATA == b.originIATA, gap > minGap, gap <= maxGap {
                    pairs.append((a, b))
                }
            }
        }
        return pairs
    }

    // MARK: - Persistence

    private static var fileURL: URL {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("flights.json")
    }

    private func sort() {
        flights.sort { $0.sortDate < $1.sortDate }
    }

    private func save() {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = .prettyPrinted
        if let data = try? encoder.encode(flights) {
            try? data.write(to: Self.fileURL, options: .atomic)
        }
    }

    private func load() {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        if let data = try? Data(contentsOf: Self.fileURL),
           let decoded = try? decoder.decode([Flight].self, from: data) {
            flights = decoded
        }
    }
}
