import Foundation
import Combine

/// The rolling punctuality record behind the arrival forecast.
///
/// Two things feed it: flights the user actually took (recorded automatically
/// when they land) and backfilled history for a route the user is about to fly.
/// Everything is persisted to Application Support as JSON, pruned on load, and
/// de-duplicated so re-recording the same leg can't skew the statistics.
@MainActor
final class DelayHistoryStore: ObservableObject {

    /// Window and retention live on `DelayObservation` so the forecaster can
    /// read them without touching a main-actor type.
    static var windowDays: Int { DelayObservation.analysisWindowDays }
    static var retentionDays: Int { DelayObservation.retentionDays }

    @Published private(set) var observations: [DelayObservation] = []
    @Published private(set) var lastBackfill: [String: Date] = [:]

    init() {
        load()
        prune()
    }

    // MARK: - Reading

    /// Observations inside the analysis window, newest first.
    func window(days: Int = DelayObservation.analysisWindowDays,
                now: Date = .now) -> [DelayObservation] {
        let cutoff = now.addingTimeInterval(-Double(days) * 86_400)
        return observations
            .filter { $0.scheduledDeparture >= cutoff && $0.scheduledDeparture <= now }
            .sorted { $0.scheduledDeparture > $1.scheduledDeparture }
    }

    /// Has this route been backfilled recently enough to skip re-fetching?
    func needsBackfill(originIATA: String, destinationIATA: String, now: Date = .now) -> Bool {
        let key = "\(originIATA.uppercased())-\(destinationIATA.uppercased())"
        guard let last = lastBackfill[key] else { return true }
        return now.timeIntervalSince(last) > 12 * 3600
    }

    func markBackfilled(originIATA: String, destinationIATA: String, at date: Date = .now) {
        lastBackfill["\(originIATA.uppercased())-\(destinationIATA.uppercased())"] = date
        save()
    }

    // MARK: - Writing

    /// Record a flight the user took. Safe to call repeatedly — the newest
    /// version of a leg replaces the older one rather than adding a duplicate.
    @discardableResult
    func record(flown flight: Flight, at now: Date = .now) -> Bool {
        guard let observation = DelayObservation(observed: flight, source: .flown, at: now) else {
            return false
        }
        return ingest([observation]) > 0
    }

    /// Fold in a batch. Returns how many were genuinely new or updated.
    ///
    /// A first-hand `.flown` record always wins over a `.provider` or
    /// `.simulated` one for the same leg: the user was on the plane.
    @discardableResult
    func ingest(_ incoming: [DelayObservation]) -> Int {
        guard !incoming.isEmpty else { return 0 }

        var byKey = Dictionary(observations.map { ($0.dedupKey, $0) },
                               uniquingKeysWith: { existing, _ in existing })
        var changed = 0

        for observation in incoming {
            if let existing = byKey[observation.dedupKey] {
                let isUpgrade = rank(observation.source) > rank(existing.source)
                // Same source, but the numbers moved — a flight whose actual
                // arrival firmed up after we first recorded it.
                let isCorrection = rank(observation.source) == rank(existing.source)
                    && (observation.arrivalDelayMinutes != existing.arrivalDelayMinutes
                        || observation.departureDelayMinutes != existing.departureDelayMinutes
                        || observation.wasCancelled != existing.wasCancelled)
                guard isUpgrade || isCorrection else { continue }
                var replacement = observation
                replacement.id = existing.id      // keep identity stable for the UI
                byKey[observation.dedupKey] = replacement
            } else {
                byKey[observation.dedupKey] = observation
            }
            changed += 1
        }

        guard changed > 0 else { return 0 }
        observations = byKey.values.sorted { $0.scheduledDeparture > $1.scheduledDeparture }
        prune()
        save()
        return changed
    }

    private func rank(_ source: DelayObservation.Source) -> Int {
        switch source {
        case .flown: return 3
        case .provider: return 2
        case .simulated: return 1
        }
    }

    func clearAll() {
        observations = []
        lastBackfill = [:]
        save()
    }

    /// Drop anything past the retention horizon, and any simulated record once
    /// real data exists for the same leg.
    private func prune(now: Date = .now) {
        let cutoff = now.addingTimeInterval(-Double(DelayObservation.retentionDays) * 86_400)
        observations.removeAll { $0.scheduledDeparture < cutoff }
    }

    // MARK: - Persistence

    private struct Payload: Codable {
        var observations: [DelayObservation]
        var lastBackfill: [String: Date]
    }

    private static var fileURL: URL {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("delay-history.json")
    }

    private func save() {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let payload = Payload(observations: observations, lastBackfill: lastBackfill)
        if let data = try? encoder.encode(payload) {
            try? data.write(to: Self.fileURL, options: .atomic)
        }
    }

    private func load() {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        guard let data = try? Data(contentsOf: Self.fileURL),
              let payload = try? decoder.decode(Payload.self, from: data) else { return }
        observations = payload.observations.sorted { $0.scheduledDeparture > $1.scheduledDeparture }
        lastBackfill = payload.lastBackfill
    }
}
