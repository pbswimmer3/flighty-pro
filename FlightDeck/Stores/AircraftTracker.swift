import Foundation
import Combine

/// Follows one airframe by callsign, keeping the same kinematic state and
/// reconciliation the traffic map uses — so the user's own aircraft moves as
/// one continuous motion instead of jumping on every refresh.
///
/// It spends from the same adsb.lol budget as everything else (`AdsbClient`),
/// so it asks only when someone is looking and nobody else has just told it:
///
/// * **Only while on screen.** Screens report in with `setVisible(_:on:)`.
///   With none showing the aircraft — the flight page left open in another
///   tab, say — the loop idles instead of polling every interval until the
///   app backgrounds. This is *not* `stop()`: see the lifetime note in
///   `FlightMapView`.
/// * **Not twice for the same data.** The tracking map's radius search is
///   centred on this aircraft, so it nearly always contains it; the map hands
///   that report over with `ingest(_:)` and the by-callsign request is skipped
///   while those keep arriving.
@MainActor
final class AircraftTracker: ObservableObject {
    @Published private(set) var track: TrafficStore.Track?
    @Published private(set) var lastUpdate: Date?
    @Published private(set) var isSearching = false

    private var pollTask: Task<Void, Never>?
    private var callSign: String?
    private var baseInterval: TimeInterval = 15
    /// Screens currently showing this aircraft.
    private var viewers: Set<String> = []
    /// Last time a fix arrived through `ingest(_:)` rather than our own poll.
    private var lastFedAt: Date?
    /// How long a fed fix stands in for our own request. Generous on purpose:
    /// the feeder's own pace stretches as the quota runs down (`AdsbClient`),
    /// and a by-callsign request racing it would only spend the same budget
    /// twice. It's the drop limit — past that the fix wouldn't be held anyway.
    private let feedGrace: TimeInterval = DeadReckoning.Limits.dropAfter

    deinit { pollTask?.cancel() }

    /// Fifteen seconds by default, not five: dead reckoning, not the sample
    /// rate, keeps the aircraft moving, and five-second polling of two
    /// endpoints is what spent the day's adsb.lol quota in twenty minutes.
    func start(callSign: String, interval: TimeInterval = 15) {
        let cs = callSign.trimmingCharacters(in: .whitespaces).uppercased()
        guard !cs.isEmpty else { return }
        if pollTask != nil, self.callSign == cs, baseInterval == interval { return }

        self.callSign = cs
        baseInterval = interval
        if track == nil { isSearching = true }
        launch()
    }

    func stop() {
        pollTask?.cancel()
        pollTask = nil
        isSearching = false
    }

    /// A screen showing this aircraft came on or went off screen. A set, not a
    /// count, so a repeated `onAppear` can't leave it stuck "visible"; and the
    /// order SwiftUI fires the two sides of a push in doesn't matter.
    func setVisible(_ visible: Bool, on screen: String) {
        let wasIdle = viewers.isEmpty
        if visible { viewers.insert(screen) } else { viewers.remove(screen) }
        // Whoever was feeding us may just have gone (popping the tracking map
        // back to the flight page): resume our own cadence rather than sit out
        // the rest of `feedGrace` with a fix going stale on screen.
        lastFedAt = nil
        // Back on screen after an idle spell: look now, rather than finishing
        // a sleep that may have most of an interval left to run.
        if wasIdle, !viewers.isEmpty, pollTask != nil { launch() }
    }

    /// A fix for this airframe that arrived some other way — in practice the
    /// tracking map's radius search, which already contains it.
    func ingest(_ report: TrafficReport) {
        apply(report)
        lastFedAt = lastUpdate
    }

    private func apply(_ report: TrafficReport) {
        let now = Date.now
        if var existing = track, existing.report.hex == report.hex {
            existing.ingest(report, at: now)
            track = existing
        } else {
            track = TrafficStore.Track.begin(report, at: now)
        }
        lastUpdate = now
        isSearching = false
    }

    private var currentInterval: TimeInterval {
        ProcessInfo.processInfo.isLowPowerModeEnabled ? baseInterval * 2 : baseInterval
    }

    private func launch() {
        pollTask?.cancel()
        pollTask = Task { [weak self] in
            while !Task.isCancelled {
                // Don't hold `self` through the sleep, which can now run to a
                // rate limit's end: `deinit` (the flight page being popped) is
                // what stops this loop, and it can't run while the loop holds
                // the tracker.
                guard let wait = await self?.pollIfDue() else { return }
                try? await Task.sleep(nanoseconds: UInt64(max(wait, 1) * 1_000_000_000))
            }
        }
    }

    /// One turn of the loop; returns how long to sleep before the next.
    private func pollIfDue() async -> TimeInterval {
        let interval = currentInterval
        guard let callSign, !viewers.isEmpty else { return interval }

        let now = Date.now
        // The tracking map's search is supplying this aircraft: leave it to
        // that. If the aircraft drops out of it, we resume within `feedGrace`.
        if let lastFedAt, now.timeIntervalSince(lastFedAt) < feedGrace { return interval }
        // A fix only moments old (say, relaunched straight after one): wait
        // out the rest of the interval instead of asking again.
        if let lastUpdate {
            let age = now.timeIntervalSince(lastUpdate)
            if age < interval - 1 { return interval - age }
        }

        do {
            let report = try await AdsbService.shared.report(callSign: callSign)
            guard !Task.isCancelled else { return interval }
            isSearching = false
            if let report {
                apply(report)
            } else {
                // Out of coverage. Hold the last track briefly — receivers
                // drop in and out constantly — but once it's older than the
                // drop limit, let go so the map falls back to the route-based
                // estimate rather than showing a frozen aircraft that looks
                // live.
                pruneStale()
            }
            return interval
        } catch AdsbClient.Failure.rateLimited(until: let until) {
            guard !Task.isCancelled else { return interval }
            isSearching = false
            pruneStale()
            // The client refuses everything until then; don't wake to ask.
            return max(interval, until.timeIntervalSinceNow)
        } catch {
            guard !Task.isCancelled else { return interval }
            isSearching = false
            pruneStale()
            return interval
        }
    }

    /// Drop a track we've extrapolated past the point of usefulness.
    private func pruneStale(at now: Date = .now) {
        if let track, now.timeIntervalSince(track.measured.validAt) > DeadReckoning.Limits.dropAfter {
            self.track = nil
        }
    }
}
