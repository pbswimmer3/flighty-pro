import Foundation
import Combine

/// Source of truth for the user's tracked flights. Persists to a JSON file in
/// Application Support and periodically refreshes active flights.
@MainActor
final class FlightStore: ObservableObject {
    @Published private(set) var flights: [Flight] = []
    @Published var lastRefresh: Date?

    private let settings: SettingsStore
    private var refreshTimer: Timer?

    init(settings: SettingsStore) {
        self.settings = settings
        load()
        if flights.isEmpty && settings.demoMode {
            flights = DemoFlightProvider.sampleFlights()
            save()
        }
        // Re-evaluate live flights every 90 seconds while the app is open.
        refreshTimer = Timer.scheduledTimer(withTimeInterval: 90, repeats: true) { [weak self] _ in
            Task { @MainActor in await self?.refreshActive() }
        }
    }

    deinit { refreshTimer?.invalidate() }

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

    var todayFlights: [Flight] {
        flights.filter { Calendar.current.isDateInToday($0.scheduledDeparture) || $0.effectivePhase.isAirborne }
    }
    var upcomingFlights: [Flight] {
        flights.filter {
            !Calendar.current.isDateInToday($0.scheduledDeparture)
                && $0.scheduledDeparture > .now
                && !$0.effectivePhase.isAirborne
        }
    }
    var pastFlights: [Flight] {
        flights.filter {
            !Calendar.current.isDateInToday($0.scheduledDeparture)
                && $0.scheduledDeparture <= .now
                && !$0.effectivePhase.isAirborne
        }
        .sorted { $0.scheduledDeparture > $1.scheduledDeparture }
    }

    // MARK: - Connection detection

    /// Flight pairs that look like connections: leg 1 arrives where leg 2
    /// departs, with a 20 min – 24 h gap.
    var detectedConnections: [(inbound: Flight, outbound: Flight)] {
        var pairs: [(Flight, Flight)] = []
        let sorted = flights.sorted { $0.scheduledDeparture < $1.scheduledDeparture }
        for (i, a) in sorted.enumerated() {
            for b in sorted.dropFirst(i + 1) {
                let gap = b.scheduledDeparture.timeIntervalSince(a.scheduledArrival)
                if a.destinationIATA == b.originIATA, gap > 20 * 60, gap < 24 * 3600 {
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
