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
    @StateObject private var routes = RouteLookup()
    @State private var selectedHex: String?

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
            .onTapGesture { (point: CGPoint) in
                selectTrack(near: point, proxy: proxy)
            }
            .overlay(alignment: .top) { statusBar }
            .overlay(alignment: .bottomLeading) { legend }
            .overlay(alignment: .bottom) { selectedCard }
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
        // The callout is drawn after the loop so no later symbol paints over
        // it, which is also why the anchor is carried out rather than drawn
        // in place.
        var selectedAnchor: (point: CGPoint, size: CGFloat)?

        for track in visibleTracks {
            let rendered = track.state(at: now)
            guard let point = proxy.convert(rendered.coordinate, to: .local) else { continue }
            // Cheap cull — off-screen aircraft still cost a conversion, not a draw.
            guard point.x > -40, point.y > -40,
                  point.x < size.width + 40, point.y < size.height + 40 else { continue }

            let isOwn = track.report.hex == highlightHex
            let isSelected = track.report.hex == selectedHex
            let style = TrafficSymbol(report: track.report, isOwn: isOwn, isStale: rendered.isStale)

            if isOwn, let accuracy = track.report.accuracyMetres {
                drawAccuracyRing(&context, at: point, metres: accuracy,
                                 proxy: proxy, coordinate: rendered.coordinate)
            }

            AircraftGlyph.draw(&context, at: point,
                               heading: rendered.headingDegrees,
                               hasHeading: track.report.headingDegrees != nil,
                               style: style,
                               isSelected: isSelected)

            if isSelected { selectedAnchor = (point, style.size) }
        }

        // Only the tapped aircraft is labelled. Labelling every mover meant
        // that at a hub the apron disappeared under overlapping callsigns —
        // and a callsign on its own doesn't answer the question people
        // actually have, which is where that aircraft is going.
        if let anchor = selectedAnchor, let track = selectedTrack {
            let route = routes.route(for: track.report.callsign)
            let subtitle = route?.arrow
                ?? (routes.isLoading(track.report.callsign) ? "Looking up route…" : nil)
            AircraftGlyph.drawCallout(&context,
                                      at: CGPoint(x: anchor.point.x, y: anchor.point.y + anchor.size + 9),
                                      title: route?.displayNumber ?? track.report.label,
                                      subtitle: subtitle,
                                      width: size.width)
        }
    }

    // MARK: - Selection

    /// Nearest aircraft to the tap, within a finger's width. Hit testing is
    /// manual because the symbols live in a single `Canvas` that deliberately
    /// passes gestures through to the map underneath.
    private func selectTrack(near point: CGPoint, proxy: MapProxy) {
        let now = Date.now
        var best: (hex: String, distance: CGFloat)?

        for track in visibleTracks {
            let rendered = track.state(at: now)
            guard let candidate = proxy.convert(rendered.coordinate, to: .local) else { continue }
            let distance = hypot(candidate.x - point.x, candidate.y - point.y)
            if distance < 28, distance < (best?.distance ?? .greatestFiniteMagnitude) {
                best = (track.report.hex, distance)
            }
        }

        let newSelection = (best?.hex == selectedHex) ? nil : best?.hex
        withAnimation(.easeInOut(duration: 0.15)) {
            selectedHex = newSelection
        }
        if let hex = newSelection,
           let callsign = visibleTracks.first(where: { $0.report.hex == hex })?.report.callsign {
            routes.lookup(callsign)
        }
    }

    private var selectedTrack: TrafficStore.Track? {
        guard let selectedHex else { return nil }
        return visibleTracks.first { $0.report.hex == selectedHex }
    }

    @ViewBuilder
    private var selectedCard: some View {
        if let track = selectedTrack {
            let report = track.report
            HStack(spacing: 10) {
                Image(systemName: report.onGround ? "airplane" : "airplane.circle.fill")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(report.onGround ? Theme.cyan : Theme.accent)

                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text(report.label)
                            .font(.system(size: 14, weight: .heavy, design: .rounded))
                        if let type = report.icaoType {
                            Text(type)
                                .font(Theme.monoFont(10, weight: .medium))
                                .foregroundStyle(Theme.textTertiary)
                        }
                    }
                    if let route = routes.route(for: report.callsign) {
                        Text(route.arrow)
                            .font(.system(size: 13, weight: .heavy, design: .rounded))
                            .foregroundStyle(Theme.accent)
                    } else if routes.isLoading(report.callsign) {
                        Text("Looking up route…")
                            .font(.system(size: 11, weight: .medium, design: .rounded))
                            .foregroundStyle(Theme.textTertiary)
                    } else if routes.isUnknown(report.callsign) {
                        Text("Route unknown")
                            .font(.system(size: 11, weight: .medium, design: .rounded))
                            .foregroundStyle(Theme.textTertiary)
                    }
                    Text(detailLine(report))
                        .font(.system(size: 11, weight: .medium, design: .rounded))
                        .foregroundStyle(Theme.textSecondary)
                }

                Spacer()

                Button {
                    withAnimation(.easeInOut(duration: 0.15)) { selectedHex = nil }
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 17))
                        .foregroundStyle(Theme.textTertiary)
                }
                .buttonStyle(.plain)
            }
            .padding(11)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .padding(.horizontal, 10)
            .padding(.bottom, 10)
        }
    }

    private func detailLine(_ report: TrafficReport) -> String {
        var parts: [String] = []
        if report.onGround {
            parts.append(report.isStationary ? "Parked" : "Taxiing")
        } else if let altitude = report.altitudeFeet {
            parts.append("\(Fmt.grouped(altitude)) ft")
        }
        if let speed = report.groundSpeedKts { parts.append("\(Int(speed)) kt") }
        if let distance = report.distanceNM { parts.append(String(format: "%.1f nm away", distance)) }
        if let registration = report.registration, registration != report.label {
            parts.append(registration)
        }
        return parts.isEmpty ? "Live ADS-B contact" : parts.joined(separator: " · ")
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
        // Step aside for the selected-aircraft card rather than sitting under it.
        .padding(.bottom, selectedTrack == nil ? 0 : 78)
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

    /// The user's own aircraft on the flight tracking map. Has its own
    /// initialiser because it's sometimes drawn from a route estimate, where
    /// there is no ADS-B report to derive a style from.
    init(own isStale: Bool) {
        isOwn = true
        color = .white
        size = 14
        opacity = isStale ? 0.45 : 1
    }
}
