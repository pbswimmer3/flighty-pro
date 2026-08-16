import SwiftUI
import MapKit

/// Live ADS-B traffic on a map, animated as continuous motion.
///
/// Two deliberate choices here:
///
/// * **One `Canvas`, not one annotation per aircraft.** Thirty-plus MapKit
///   annotation views moving every frame thrashes; a single overlay doesn't.
/// * **`TimelineView(.animation)` drives the clock, not the network.** Each
///   frame asks the store where every aircraft *should* be at that instant,
///   so motion stays smooth between samples that arrive seconds apart.
struct LiveTrafficMapView: View {

    enum Surface {
        case satellite   // runways and taxiways are visible — use for ground views
        case standard
    }

    /// Injected so the screen around the map can read the same tracks (a
    /// ground-queue list, say) without opening a second poll.
    @ObservedObject var store: TrafficStore

    let center: CLLocationCoordinate2D
    var radiusNM: Int
    var spanMetres: CLLocationDistance
    var pollInterval: TimeInterval
    var surface: Surface
    var groundOnly: Bool
    /// Drawn prominently with its accuracy ring — the user's own aircraft.
    var highlightHex: String?
    var centerLabel: String?

    @Environment(\.scenePhase) private var scenePhase
    @State private var camera: MapCameraPosition

    init(store: TrafficStore,
         center: CLLocationCoordinate2D,
         radiusNM: Int = 10,
         spanMetres: CLLocationDistance = 14_000,
         pollInterval: TimeInterval = 5,
         surface: Surface = .satellite,
         groundOnly: Bool = false,
         highlightHex: String? = nil,
         centerLabel: String? = nil) {
        self.store = store
        self.center = center
        self.radiusNM = radiusNM
        self.spanMetres = spanMetres
        self.pollInterval = pollInterval
        self.surface = surface
        self.groundOnly = groundOnly
        self.highlightHex = highlightHex
        self.centerLabel = centerLabel
        _camera = State(initialValue: .region(MKCoordinateRegion(
            center: center,
            latitudinalMeters: spanMetres,
            longitudinalMeters: spanMetres)))
    }

    var body: some View {
        MapReader { proxy in
            Map(position: $camera, interactionModes: [.pan, .zoom]) {
                if let centerLabel {
                    Annotation(centerLabel, coordinate: center) {
                        Image(systemName: "mappin.circle.fill")
                            .font(.system(size: 16))
                            .foregroundStyle(Theme.accent)
                    }
                }
            }
            .mapStyle(mapStyle)
            .overlay { trafficLayer(proxy) }
            .overlay(alignment: .top) { statusBar }
            .overlay(alignment: .bottomLeading) { legend }
        }
        .onAppear { startIfActive() }
        .onDisappear { store.stop() }
        .onChange(of: scenePhase) { _, phase in
            // Zero network traffic when backgrounded.
            phase == .active ? startIfActive() : store.stop()
        }
        .onChange(of: radiusNM) { _, _ in startIfActive() }
        .onChange(of: pollInterval) { _, _ in startIfActive() }
        .onChange(of: spanMetres) { _, metres in
            withAnimation(.easeInOut(duration: 0.5)) {
                camera = .region(MKCoordinateRegion(center: center,
                                                    latitudinalMeters: metres,
                                                    longitudinalMeters: metres))
            }
        }
    }

    private var mapStyle: MapStyle {
        switch surface {
        case .satellite: return .imagery(elevation: .flat)
        case .standard: return .standard(elevation: .flat, pointsOfInterest: .excludingAll)
        }
    }

    private func startIfActive() {
        store.start(near: center, radiusNM: radiusNM, interval: pollInterval)
    }

    private var visibleTracks: [TrafficStore.Track] {
        groundOnly ? store.tracks.filter(\.report.onGround) : store.tracks
    }

    // MARK: - The moving layer

    private func trafficLayer(_ proxy: MapProxy) -> some View {
        TimelineView(.animation(minimumInterval: frameInterval, paused: scenePhase != .active)) { timeline in
            Canvas { context, size in
                draw(&context, size: size, proxy: proxy, now: timeline.date)
            }
        }
        .allowsHitTesting(false)   // gestures belong to the map underneath
    }

    /// Full display rate normally; 30 fps in Low Power Mode.
    private var frameInterval: Double? {
        ProcessInfo.processInfo.isLowPowerModeEnabled ? 1.0 / 30.0 : nil
    }

    private func draw(_ context: inout GraphicsContext,
                      size: CGSize,
                      proxy: MapProxy,
                      now: Date) {
        // Labels are the expensive part; only the movers and the user's own
        // aircraft earn one. Even then they're placed against a claimed-space
        // list — at a hub, a dozen taxiing aircraft sit close enough together
        // that unchecked labels overprint into an unreadable smear.
        let labelBudget = 12
        var claimed: [CGRect] = []

        for track in visibleTracks {
            let rendered = track.state(at: now)
            guard let point = proxy.convert(rendered.coordinate, to: .local) else { continue }
            // Cheap cull — off-screen aircraft still cost a conversion, not a draw.
            guard point.x > -40, point.y > -40,
                  point.x < size.width + 40, point.y < size.height + 40 else { continue }

            let isOwn = track.report.hex == highlightHex
            let style = TrafficSymbol(report: track.report, isOwn: isOwn, isStale: rendered.isStale)

            if isOwn, let accuracy = track.report.accuracyMetres {
                drawAccuracyRing(&context, at: point, metres: accuracy,
                                 proxy: proxy, coordinate: rendered.coordinate)
            }

            drawSymbol(&context, at: point, heading: rendered.headingDegrees,
                       hasHeading: track.report.headingDegrees != nil, style: style)

            let deservesLabel = isOwn || (track.report.onGround && !track.report.isStationary)
            guard deservesLabel, claimed.count < labelBudget, let text = label(for: track) else { continue }

            let origin = CGPoint(x: point.x, y: point.y + style.size + 8)
            // Rough box: 5 pt per character is close enough for 9 pt rounded.
            let box = CGRect(x: origin.x - CGFloat(text.count) * 2.5, y: origin.y,
                             width: CGFloat(text.count) * 5, height: 11)
            guard !claimed.contains(where: { $0.intersects(box) }) else { continue }
            claimed.append(box)

            context.draw(Text(text)
                .font(.system(size: 9, weight: .bold, design: .rounded))
                .foregroundStyle(style.color.opacity(style.opacity)),
                         at: origin, anchor: .top)
        }
    }

    private func label(for track: TrafficStore.Track) -> String? {
        let name = track.report.label
        guard let speed = track.report.groundSpeedKts, speed >= DeadReckoning.Limits.stationaryKts
        else { return name }
        return "\(name) · \(Int(speed))kt"
    }

    private func drawSymbol(_ context: inout GraphicsContext,
                            at point: CGPoint,
                            heading: Double,
                            hasHeading: Bool,
                            style: TrafficSymbol) {
        context.drawLayer { layer in
            layer.translateBy(x: point.x, y: point.y)
            layer.opacity = style.opacity

            guard hasHeading else {
                // No heading in the report — a rotated symbol would be a claim
                // we can't support, so draw an unoriented dot instead.
                let r = style.size * 0.45
                layer.fill(Path(ellipseIn: CGRect(x: -r, y: -r, width: r * 2, height: r * 2)),
                           with: .color(style.color))
                return
            }

            layer.rotate(by: .degrees(heading))
            let path = Self.aircraftPath(size: style.size)
            layer.fill(path, with: .color(style.color))
            layer.stroke(path, with: .color(.black.opacity(0.55)), lineWidth: 0.75)
            if style.isOwn {
                layer.stroke(path, with: .color(.white), lineWidth: 1.5)
            }
        }
    }

    /// Confidence radius from NACp, for the user's own aircraft only — on every
    /// target it's visual noise.
    private func drawAccuracyRing(_ context: inout GraphicsContext,
                                  at point: CGPoint,
                                  metres: Double,
                                  proxy: MapProxy,
                                  coordinate: CLLocationCoordinate2D) {
        let edge = GreatCircle.destination(from: coordinate, bearingDegrees: 90, distanceMetres: metres)
        guard let edgePoint = proxy.convert(edge, to: .local) else { return }
        let radius = abs(edgePoint.x - point.x)
        guard radius > 6, radius < 400 else { return }   // invisible, or absurd at this zoom
        let rect = CGRect(x: point.x - radius, y: point.y - radius,
                          width: radius * 2, height: radius * 2)
        context.fill(Path(ellipseIn: rect), with: .color(Theme.accent.opacity(0.12)))
        context.stroke(Path(ellipseIn: rect), with: .color(Theme.accent.opacity(0.5)), lineWidth: 1)
    }

    /// A delta pointing at 0° (north), rotated to heading at draw time.
    private static func aircraftPath(size s: CGFloat) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: 0, y: -s))
        path.addLine(to: CGPoint(x: s * 0.62, y: s * 0.75))
        path.addLine(to: CGPoint(x: 0, y: s * 0.35))
        path.addLine(to: CGPoint(x: -s * 0.62, y: s * 0.75))
        path.closeSubpath()
        return path
    }

    // MARK: - Chrome

    @ViewBuilder
    private var statusBar: some View {
        HStack(spacing: 6) {
            switch store.status {
            case .idle, .loading:
                ProgressView().controlSize(.mini).tint(.white)
                Text("Finding aircraft…")
            case .live:
                // Count what's actually on screen — in a ground-only view,
                // quoting every airborne contact too would be a lie.
                let shown = visibleTracks.count
                Circle().fill(shown > 0 ? Theme.green : Theme.orange).frame(width: 6, height: 6)
                Text(shown == 1 ? "1 aircraft" : "\(shown) aircraft")
                if let last = store.lastUpdate {
                    Text("· \(Fmt.secondsAgo(last))")
                        .foregroundStyle(Theme.textSecondary)
                }
            case .noCoverage:
                Image(systemName: "antenna.radiowaves.left.and.right.slash")
                Text("No ADS-B coverage here")
            case .failed(let message):
                Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(Theme.orange)
                Text(message).lineLimit(1)
            }
        }
        .font(.system(size: 11, weight: .bold, design: .rounded))
        .foregroundStyle(Theme.textPrimary)
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(.black.opacity(0.65), in: Capsule())
        .padding(.top, 10)
    }

    private var legend: some View {
        VStack(alignment: .leading, spacing: 3) {
            if groundOnly {
                legendRow(Theme.cyan, "Taxiing")
                legendRow(Theme.textSecondary, "Parked")
            } else {
                legendRow(Theme.cyan, "On ground")
                legendRow(Theme.green, "Below 10,000 ft")
                legendRow(Theme.accent, "10–25,000 ft")
                legendRow(Theme.purple, "Above 25,000 ft")
            }
        }
        .padding(8)
        .background(.black.opacity(0.55), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .padding(10)
    }

    private func legendRow(_ color: Color, _ text: String) -> some View {
        HStack(spacing: 5) {
            Circle().fill(color).frame(width: 6, height: 6)
            Text(text)
                .font(.system(size: 9, weight: .semibold, design: .rounded))
                .foregroundStyle(Theme.textPrimary)
        }
    }
}

/// How one aircraft should look: colour by altitude band, size by importance,
/// and a visible fade once the position is more extrapolation than measurement.
struct TrafficSymbol {
    var color: Color
    var size: CGFloat
    var opacity: Double
    var isOwn: Bool

    init(report: TrafficReport, isOwn: Bool, isStale: Bool) {
        self.isOwn = isOwn
        if isOwn {
            color = .white
            size = 13
        } else if report.onGround {
            color = report.isStationary ? Theme.textSecondary : Theme.cyan
            size = report.isStationary ? 5 : 7
        } else {
            switch report.altitudeFeet ?? 0 {
            case ..<10_000: color = Theme.green
            case ..<25_000: color = Theme.accent
            default: color = Theme.purple
            }
            size = 9
        }
        // MLAT positions are triangulated by receivers rather than reported by
        // the aircraft — dimmer, because they're genuinely less certain.
        var alpha = report.isMLAT ? 0.65 : 1.0
        if isStale { alpha *= 0.35 }
        opacity = alpha
    }
}
