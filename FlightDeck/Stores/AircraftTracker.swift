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
    private var leg: (origin: String, destination: String)?
    private var baseInterval: TimeInterval = 5

    deinit { pollTask?.cancel() }

    /// `leg` is the user's origin and destination IATA codes. A callsign is a
    /// flight number, and airlines fly the same number on several legs a day
    /// (AS2187 SNA→SFO and then SFO→LAX), so a callsign match alone can be the
    /// *other* leg's airframe. When given, a contact whose known route doesn't
    /// serve both airports is ignored.
    func start(callSign: String, leg: (origin: String, destination: String)? = nil,
               interval: TimeInterval = 5) {
        let cs = callSign.trimmingCharacters(in: .whitespaces).uppercased()
        guard !cs.isEmpty else { return }
        let wantedLeg = leg.map { (origin: $0.origin.uppercased(), destination: $0.destination.uppercased()) }
        if pollTask != nil, self.callSign == cs, baseInterval == interval,
           self.leg?.origin == wantedLeg?.origin, self.leg?.destination == wantedLeg?.destination { return }

        self.callSign = cs
        self.leg = wantedLeg
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
        var report = await AdsbService.shared.report(callSign: callSign)
        if report != nil, let leg, let route = await FlightRouteService.shared.route(for: callSign) {
            // The table is a schedule, so only a clear mismatch rejects: an
            // unknown route (the common miss) still gets the benefit of the doubt.
            let stops = ([route.origin.iata] + [route.midpoint?.iata].compactMap { $0 } + [route.destination.iata])
                .map { $0.uppercased() }
            if !stops.contains(leg.origin) || !stops.contains(leg.destination) { report = nil }
        }
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
