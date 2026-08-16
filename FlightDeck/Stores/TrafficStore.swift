import Foundation
import Combine
import CoreLocation

/// Holds the live picture of nearby aircraft: polls `TrafficService`, keeps a
/// kinematic state per airframe, and reconciles new fixes into it instead of
/// replacing them.
///
/// Rendering reads `state(at:)` at display rate — polling faster would burn
/// battery and rate limit without making anything smoother.
@MainActor
final class TrafficStore: ObservableObject {

    /// One airframe's continuous history: the newest measurement, plus where it
    /// was being drawn when that measurement landed so we can ease between them.
    struct Track: Identifiable {
        var report: TrafficReport
        var measured: KinematicState
        /// Where the icon actually was when the newest fix arrived. `nil` for a
        /// target we've only seen once — nothing to blend from yet.
        var blendFrom: KinematicState?
        var blendStartedAt: Date
        var lastReportAt: Date

        var id: String { report.hex }

        struct Rendered {
            var coordinate: CLLocationCoordinate2D
            var headingDegrees: Double
            var age: TimeInterval
            var isStale: Bool
        }

        func state(at time: Date) -> Rendered {
            let target = DeadReckoning.project(measured, to: time)
            var coordinate = target
            var heading = measured.headingDegrees

            if let blendFrom {
                let progress = time.timeIntervalSince(blendStartedAt)
                    / DeadReckoning.Limits.reconcileDuration
                if progress < 1 {
                    // Keep the *old* state moving too, so the blend is between
                    // two moving points — otherwise the plane visibly slows
                    // down during every reconciliation.
                    let from = DeadReckoning.project(blendFrom, to: time)
                    let eased = DeadReckoning.ease(progress)
                    coordinate = DeadReckoning.interpolate(from, target, eased)
                    heading = DeadReckoning.blendAngle(from: blendFrom.headingDegrees,
                                                       to: measured.headingDegrees,
                                                       progress: eased)
                }
            }

            let age = time.timeIntervalSince(measured.validAt)
            return Rendered(coordinate: coordinate,
                            headingDegrees: heading,
                            age: age,
                            isStale: age > DeadReckoning.Limits.staleAfter)
        }

        static func begin(_ report: TrafficReport, at now: Date) -> Track {
            Track(report: report,
                  measured: KinematicState(report),
                  blendFrom: nil,
                  blendStartedAt: now,
                  lastReportAt: now)
        }

        /// Fold a new report in. Never snaps: the position the icon currently
        /// occupies becomes the start of a short ease onto the new fix.
        mutating func ingest(_ report: TrafficReport, at now: Date) {
            let incoming = KinematicState(report)
            // Only reconcile toward a genuinely newer fix. Responses often
            // repeat the same position, and restarting the blend each time
            // would stutter the icon in place.
            if incoming.validAt > measured.validAt {
                let rendered = state(at: now)
                blendFrom = KinematicState(coordinate: rendered.coordinate,
                                           headingDegrees: rendered.headingDegrees,
                                           groundSpeedKts: measured.groundSpeedKts,
                                           validAt: now)
                blendStartedAt = now
                measured = incoming
            }
            self.report = report
            lastReportAt = now
        }
    }

    enum Status: Equatable {
        case idle
        case loading
        case live(count: Int)
        case noCoverage
        case failed(String)
    }

    @Published private(set) var tracks: [Track] = []
    @Published private(set) var status: Status = .idle
    @Published private(set) var lastUpdate: Date?

    /// Aircraft coverage drops in and out constantly; removing a target the
    /// first time it's missing from a response makes the map flicker.
    private let disappearanceGrace: TimeInterval = 20

    private var pollTask: Task<Void, Never>?
    private var center: CLLocationCoordinate2D?
    private var radiusNM: Int = 10
    private var baseInterval: TimeInterval = 5

    var isRunning: Bool { pollTask != nil }

    deinit { pollTask?.cancel() }

    // MARK: - Lifecycle

    /// Begin polling. Safe to call repeatedly — a changed centre or radius
    /// restarts the loop, an identical one is ignored.
    func start(near center: CLLocationCoordinate2D, radiusNM: Int, interval: TimeInterval) {
        if isRunning,
           let existing = self.center,
           abs(existing.latitude - center.latitude) < 0.0001,
           abs(existing.longitude - center.longitude) < 0.0001,
           self.radiusNM == radiusNM,
           self.baseInterval == interval {
            return
        }

        self.center = center
        self.radiusNM = radiusNM
        self.baseInterval = interval

        pollTask?.cancel()
        if tracks.isEmpty { status = .loading }
        pollTask = Task { [weak self] in
            while !Task.isCancelled {
                guard let self else { return }
                await self.poll()
                let wait = self.currentInterval
                try? await Task.sleep(nanoseconds: UInt64(wait * 1_000_000_000))
            }
        }
    }

    /// Stop all network activity — call when the map leaves the screen or the
    /// app backgrounds. Nothing polls in the background, by design.
    func stop() {
        pollTask?.cancel()
        pollTask = nil
    }

    /// Low Power Mode halves the poll rate. Motion quality is unaffected: it
    /// comes from extrapolation, not from the sample rate.
    private var currentInterval: TimeInterval {
        ProcessInfo.processInfo.isLowPowerModeEnabled ? baseInterval * 2 : baseInterval
    }

    // MARK: - Polling

    private func poll() async {
        guard let center else { return }
        do {
            let reports = try await TrafficService.shared.traffic(near: center, radiusNM: radiusNM)
            guard !Task.isCancelled else { return }
            merge(reports, at: .now)
            lastUpdate = .now
            status = tracks.isEmpty ? .noCoverage : .live(count: tracks.count)
        } catch {
            guard !Task.isCancelled else { return }
            // Keep showing what we have — a dropped poll shouldn't clear the map.
            status = .failed(error.localizedDescription)
        }
    }

    private func merge(_ reports: [TrafficReport], at now: Date) {
        var byHex = Dictionary(tracks.map { ($0.id, $0) }, uniquingKeysWith: { _, latest in latest })

        for report in reports {
            if var existing = byHex[report.hex] {
                existing.ingest(report, at: now)
                byHex[report.hex] = existing
            } else {
                byHex[report.hex] = Track.begin(report, at: now)
            }
        }

        tracks = byHex.values
            .filter { now.timeIntervalSince($0.lastReportAt) < disappearanceGrace }
            .filter { now.timeIntervalSince($0.measured.validAt) < DeadReckoning.Limits.dropAfter }
            // Stable order keeps Canvas draw order (and therefore overlap)
            // from shuffling between frames.
            .sorted { $0.id < $1.id }
    }
}
