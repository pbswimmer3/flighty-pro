import Foundation
import Combine

/// Follows one airframe by callsign, keeping the same kinematic state and
/// reconciliation the traffic map uses — so the user's own aircraft moves as
/// one continuous motion instead of jumping on every refresh.
@MainActor
final class AircraftTracker: ObservableObject {
    @Published private(set) var track: TrafficStore.Track?
    @Published private(set) var lastUpdate: Date?
    @Published private(set) var isSearching = false

    private var pollTask: Task<Void, Never>?
    private var callSign: String?
    private var baseInterval: TimeInterval = 5

    deinit { pollTask?.cancel() }

    func start(callSign: String, interval: TimeInterval = 5) {
        let cs = callSign.trimmingCharacters(in: .whitespaces).uppercased()
        guard !cs.isEmpty else { return }
        if pollTask != nil, self.callSign == cs, baseInterval == interval { return }

        self.callSign = cs
        baseInterval = interval
        pollTask?.cancel()
        if track == nil { isSearching = true }

        pollTask = Task { [weak self] in
            while !Task.isCancelled {
                guard let self else { return }
                await self.poll()
                let wait = self.currentInterval
                try? await Task.sleep(nanoseconds: UInt64(wait * 1_000_000_000))
            }
        }
    }

    func stop() {
        pollTask?.cancel()
        pollTask = nil
        isSearching = false
    }

    private var currentInterval: TimeInterval {
        ProcessInfo.processInfo.isLowPowerModeEnabled ? baseInterval * 2 : baseInterval
    }

    private func poll() async {
        guard let callSign else { return }
        let report = await AdsbService.shared.report(callSign: callSign)
        guard !Task.isCancelled else { return }
        isSearching = false

        guard let report else {
            // Out of coverage. Hold the last track briefly — receivers drop in
            // and out constantly — but once it's older than the drop limit,
            // let go so the map falls back to the route-based estimate rather
            // than showing a frozen aircraft that looks live.
            pruneStale()
            return
        }

        let now = Date.now
        if var existing = track, existing.report.hex == report.hex {
            existing.ingest(report, at: now)
            track = existing
        } else {
            track = TrafficStore.Track.begin(report, at: now)
        }
        lastUpdate = now
    }

    /// Drop a track we've extrapolated past the point of usefulness.
    private func pruneStale(at now: Date = .now) {
        if let track, now.timeIntervalSince(track.measured.validAt) > DeadReckoning.Limits.dropAfter {
            self.track = nil
        }
    }
}
