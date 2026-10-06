import SwiftUI
import MapKit

/// The live tracking screen, reached by tapping *your flight*.
///
/// This is the centre of gravity for aircraft tracking in the app: your
/// aircraft on its route, everything flying or taxiing around it, and no zoom
/// ceiling — from the whole great-circle track down to which taxiway you're
/// sitting on. Airport traffic remains its own screen for "what's happening at
/// DFW right now", but you no longer have to go through an airport to watch
/// your own flight.
///
/// Three deliberate mechanics:
///
/// * **The camera follows the aircraft but never steals the zoom.** Recentring
///   preserves whatever distance the user pinched to, and the first drag turns
///   following off.
/// * **Traffic radius follows the aircraft in jumps**, not continuously — the
///   radius search is re-anchored only once the aircraft has drifted far enough
///   that the old anchor would start clipping the picture.
/// * **One `Canvas` on a display clock draws everything that moves**, exactly
///   as `LiveTrafficMapView` does, so thirty aircraft cost one redraw rather
///   than thirty annotation updates.
struct FlightTrackingMapView: View {

    enum Scope: String, CaseIterable, Identifiable {
        case ground = "Ground"
        case nearby = "Nearby"
        case route = "Route"

        var id: String { rawValue }

        /// Radius of the ADS-B search. Ground is deliberately tight: at 5 nm
        /// the response is small enough to poll quickly and every contact is
        /// genuinely "around you".
        var radiusNM: Int {
            switch self {
            case .ground: return 5
            case .nearby: return 40
            case .route: return 90
            }
        }

        var pollInterval: TimeInterval { self == .ground ? 3 : 5 }

        /// Camera altitude used when this scope is first entered.
        var cameraDistance: CLLocationDistance {
            switch self {
            case .ground: return 4_000
            case .nearby: return 90_000
            case .route: return 1_200_000
            }
        }

        var usesSatellite: Bool { self == .ground }
    }

    let flight: Flight
    @ObservedObject var tracker: AircraftTracker

    @StateObject private var traffic = TrafficStore()
    @StateObject private var routes = RouteLookup()
    @Environment(\.scenePhase) private var scenePhase

    /// Seeded in `init`, not left as `.automatic`. Setting the position from
    /// `onAppear` is too late — MapKit has already framed the route line and
    /// annotations, and the map opens on the whole continent instead of on the
    /// aircraft, which makes tapping any traffic impossible.
    @State private var camera: MapCameraPosition
    /// Whatever the user last pinched to, so recentring doesn't reset it.
    @State private var cameraDistance: CLLocationDistance = 90_000
    @State private var isFollowing = true
    @State private var scope: Scope
    @State private var queryCenter: CLLocationCoordinate2D
    @State private var selectedHex: String?
    @State private var didAnchorCamera = false

    /// How far the aircraft may drift from the search anchor before we
    /// re-query. Roughly a third of the radius keeps the picture centred
    /// without polling on every fix.
    private var recenterThresholdNM: Double { Double(scope.radiusNM) / 3 }

    init(flight: Flight, tracker: AircraftTracker) {
        self.flight = flight
        self.tracker = tracker

        // Airborne opens on the wider picture; on the ground the interesting
        // detail is the apron you're sitting on.
        let initialScope: Scope = flight.effectivePhase.isAirborne ? .nearby : .ground
        _scope = State(initialValue: initialScope)
        _cameraDistance = State(initialValue: initialScope.cameraDistance)

        let anchor = tracker.track?.report.coordinate
            ?? AirportDatabase.shared.airport(iata: flight.originIATA)?.coordinate
            ?? AirportDatabase.shared.airport(iata: flight.destinationIATA)?.coordinate
            ?? CLLocationCoordinate2D(latitude: 0, longitude: 0)
        _queryCenter = State(initialValue: anchor)
        _camera = State(initialValue: .camera(MapCamera(centerCoordinate: anchor,
                                                        distance: initialScope.cameraDistance,
                                                        heading: 0,
                                                        pitch: 0)))
    }

    // MARK: - Geometry

    private var origin: Airport? { AirportDatabase.shared.airport(iata: flight.originIATA) }
    private var destination: Airport? { AirportDatabase.shared.airport(iata: flight.destinationIATA) }

    /// Where the user's own aircraft is, and how much we trust it.
    private struct OwnPosition {
        var coordinate: CLLocationCoordinate2D
        var heading: Double
        var hasHeading: Bool
        var isLive: Bool
        var isStale: Bool
        var onGround: Bool
        var accuracyMetres: Double?
    }

    private func ownPosition(at now: Date) -> OwnPosition? {
        if let track = tracker.track {
            let rendered = track.state(at: now)
            let hasHeading = track.report.headingDegrees != nil
            let heading = hasHeading
                ? rendered.headingDegrees
                : destination.map { GreatCircle.bearing(from: rendered.coordinate, to: $0.coordinate) } ?? 0
            return OwnPosition(coordinate: rendered.coordinate,
                               heading: heading,
                               hasHeading: true,
                               isLive: true,
                               isStale: rendered.isStale,
                               onGround: track.report.onGround,
                               accuracyMetres: track.report.accuracyMetres)
        }

        // No ADS-B contact. While the flight is in the air we can still place it
        // on the route from the clock — clearly labelled as an estimate.
        guard flight.effectivePhase.isAirborne,
              let origin, let destination else { return nil }
        let fraction = flight.progress(at: now)
        let coordinate = GreatCircle.intermediatePoint(from: origin.coordinate,
                                                       to: destination.coordinate,
                                                       fraction: fraction)
        let ahead = GreatCircle.intermediatePoint(from: origin.coordinate,
                                                  to: destination.coordinate,
                                                  fraction: min(fraction + 0.005, 1))
        let heading = fraction >= 0.995
            ? GreatCircle.bearing(from: coordinate, to: destination.coordinate)
            : GreatCircle.bearing(from: coordinate, to: ahead)
        return OwnPosition(coordinate: coordinate,
                           heading: heading,
                           hasHeading: true,
                           isLive: false,
                           isStale: false,
                           onGround: false,
                           accuracyMetres: nil)
    }

    /// Best guess at "where the user is", used to anchor both the camera and
    /// the traffic search. Before pushback that's the origin gate area; after
    /// landing it's the destination.
    private func anchorCoordinate(at now: Date = .now) -> CLLocationCoordinate2D {
        if let own = ownPosition(at: now) { return own.coordinate }
        if flight.effectivePhase.isComplete, let destination { return destination.coordinate }
        if let origin { return origin.coordinate }
        return destination?.coordinate ?? queryCenter
    }

    // MARK: - Body

    var body: some View {
        MapReader { proxy in
            Map(position: $camera, interactionModes: [.pan, .zoom, .rotate]) {
                if let origin, let destination {
                    MapPolyline(coordinates: GreatCircle.points(from: origin.coordinate,
                                                                to: destination.coordinate))
                        .stroke(Theme.accent.opacity(0.85),
                                style: StrokeStyle(lineWidth: 2.5, dash: [6, 5]))

                    Annotation(origin.iata, coordinate: origin.coordinate) { airportDot }
                    Annotation(destination.iata, coordinate: destination.coordinate) { airportDot }
                }
            }
            .mapStyle(scope.usesSatellite
                      ? .imagery(elevation: .flat)
                      : .standard(elevation: .flat, pointsOfInterest: .excludingAll))
            .overlay { movingLayer(proxy) }
            .onTapGesture { (point: CGPoint) in
                selectTrack(near: point, proxy: proxy)
            }
            // The map handles its own panning; this runs alongside purely to
            // notice that the user took the wheel.
            .simultaneousGesture(
                DragGesture(minimumDistance: 10).onChanged { _ in
                    if isFollowing { isFollowing = false }
                }
            )
            .onMapCameraChange(frequency: .onEnd) { context in
                cameraDistance = context.camera.distance
            }
        }
        .overlay(alignment: .top) { topBar }
        .overlay(alignment: .bottomTrailing) { controls }
        .overlay(alignment: .bottom) { bottomPanel }
        .ignoresSafeArea(edges: .bottom)
        .navigationTitle(flight.displayNumber)
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            anchorCameraIfNeeded()
            // Re-anchor the search before the *first* poll, for the same reason
            // `anchorCameraIfNeeded` re-aims the camera: `init` can only see the
            // live fix or the origin airport, so an airborne flight with no
            // ADS-B contact opened its first radius search over the departure
            // airport. `recenterIfDrifted` corrected it, but only on the second
            // poll — long enough to caption a thousand-mile-away apron
            // "48 on ground · just now" while the aircraft sat over Nebraska.
            queryCenter = anchorCoordinate()
            startPolling()
            startTrackingOwnAircraft()
        }
        .onDisappear { traffic.stop() }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active {
                startPolling()
                startTrackingOwnAircraft()
            } else {
                traffic.stop()
            }
        }
        .onChange(of: scope) { _, newScope in
            isFollowing = newScope != .route
            cameraDistance = newScope.cameraDistance
            selectedHex = nil
            applyCamera(animated: true)
            startPolling()
        }
        // A new ADS-B fix is the natural cadence for both recentring and
        // re-anchoring the radius search: roughly every five seconds, and never
        // faster than the data actually changes.
        .onChange(of: tracker.track?.measured.validAt) { _, _ in
            recenterIfDrifted()
            if isFollowing { applyCamera(animated: true) }
        }
        // Without an ADS-B contact there are no fixes to key off, so the poll
        // itself provides the cadence — the estimated position still moves, and
        // both the camera and the search radius have to move with it.
        .onChange(of: traffic.lastUpdate) { _, _ in
            guard tracker.track == nil else { return }
            recenterIfDrifted()
            if isFollowing { applyCamera(animated: true) }
        }
    }

    private var airportDot: some View {
        Circle()
            .fill(Theme.accent)
            .frame(width: 10, height: 10)
            .overlay(Circle().stroke(.white, lineWidth: 2))
    }

    // MARK: - Camera

    /// Corrects the seed camera once the view exists. `init` can only see the
    /// live track or the origin airport; by the time this runs, a route-based
    /// estimate is available too, so an airborne flight recentres from its
    /// origin onto the aircraft.
    private func anchorCameraIfNeeded() {
        guard !didAnchorCamera else { return }
        didAnchorCamera = true
        if scope == .route, let region = routeRegion() {
            camera = .region(region)
        } else {
            applyCamera(animated: false)
        }
    }

    private func applyCamera(animated: Bool) {
        if scope == .route, let region = routeRegion() {
            withAnimation(animated ? .easeInOut(duration: 0.6) : nil) {
                camera = .region(region)
            }
            return
        }
        let target = MapCamera(centerCoordinate: anchorCoordinate(),
                               distance: cameraDistance,
                               heading: 0,
                               pitch: 0)
        withAnimation(animated ? .easeInOut(duration: 0.9) : nil) {
            camera = .camera(target)
        }
    }

    private func routeRegion() -> MKCoordinateRegion? {
        guard let origin, let destination else { return nil }
        let midLat = (origin.lat + destination.lat) / 2
        let midLon = (origin.lon + destination.lon) / 2
        let latDelta = max(abs(origin.lat - destination.lat) * 1.6, 4)
        let lonDelta = max(abs(origin.lon - destination.lon) * 1.6, 4)
        return MKCoordinateRegion(
            center: CLLocationCoordinate2D(latitude: midLat, longitude: midLon),
            span: MKCoordinateSpan(latitudeDelta: min(latDelta, 140),
                                   longitudeDelta: min(lonDelta, 300)))
    }

    private func zoom(by factor: Double) {
        // No floor beyond MapKit's own: the whole point is being able to zoom
        // all the way in to the stand you're parked at.
        cameraDistance = min(max(cameraDistance * factor, 120), 20_000_000)
        applyCamera(animated: true)
    }

    // MARK: - Polling

    private func startPolling() {
        traffic.start(near: queryCenter, radiusNM: scope.radiusNM, interval: scope.pollInterval)
    }

    /// The flight page normally has the tracker running already; this covers
    /// coming back from the background, where it was deliberately stopped.
    private func startTrackingOwnAircraft() {
        guard flight.isLiveData, flight.isActive, let callSign = flight.callSign else { return }
        tracker.start(callSign: callSign, interval: 5)
    }

    /// Re-anchor the radius search on wherever the aircraft is now.
    ///
    /// Deliberately reads `anchorCoordinate()` rather than the ADS-B fix: with
    /// no contact the aircraft is still placed on its route from the clock, and
    /// keying off the fix alone left the traffic search sitting at the origin
    /// airport for the whole flight — the map showed the aircraft over Nebraska
    /// and the traffic list showed the apron at SFO.
    private func recenterIfDrifted() {
        let coordinate = anchorCoordinate()
        let driftNM = GreatCircle.distanceMiles(from: queryCenter, to: coordinate) / 1.15078
        guard driftNM > recenterThresholdNM else { return }
        queryCenter = coordinate
        startPolling()
    }

    // MARK: - The moving layer

    private func movingLayer(_ proxy: MapProxy) -> some View {
        TimelineView(.animation(minimumInterval: frameInterval, paused: scenePhase != .active)) { timeline in
            Canvas { context, size in
                draw(&context, size: size, proxy: proxy, now: timeline.date)
            }
        }
        .allowsHitTesting(false)
    }

    private var frameInterval: Double? {
        ProcessInfo.processInfo.isLowPowerModeEnabled ? 1.0 / 30.0 : nil
    }

    /// Everything except our own aircraft, which is drawn last and larger.
    private var otherTracks: [TrafficStore.Track] {
        let ownHex = tracker.track?.report.hex
        return traffic.tracks.filter { $0.report.hex != ownHex }
    }

    private func draw(_ context: inout GraphicsContext,
                      size: CGSize,
                      proxy: MapProxy,
                      now: Date) {
        // Where the selected aircraft ended up, so its callout can be drawn
        // last and therefore on top of every other symbol.
        var selectedAnchor: (point: CGPoint, size: CGFloat)?

        for track in otherTracks {
            let rendered = track.state(at: now)
            guard let point = proxy.convert(rendered.coordinate, to: .local) else { continue }
            guard point.x > -40, point.y > -40,
                  point.x < size.width + 40, point.y < size.height + 40 else { continue }

            let isSelected = track.report.hex == selectedHex
            let style = TrafficSymbol(report: track.report, isOwn: false, isStale: rendered.isStale)
            AircraftGlyph.draw(&context, at: point,
                               heading: rendered.headingDegrees,
                               hasHeading: track.report.headingDegrees != nil,
                               style: style,
                               isSelected: isSelected)

            if isSelected { selectedAnchor = (point, style.size) }
        }

        let ownAnchor = drawOwnAircraft(&context, size: size, proxy: proxy, now: now)

        // Labels are earned by a tap, not handed out. Printing a callsign over
        // every contact meant that in busy airspace the map was mostly text,
        // and none of it answered the question people actually have — which is
        // where that aircraft is going, not what it's called.
        if isOwnSelected, let anchor = ownAnchor {
            AircraftGlyph.drawCallout(&context,
                                      at: CGPoint(x: anchor.point.x, y: anchor.point.y + anchor.size + 9),
                                      title: flight.displayNumber,
                                      subtitle: "\(flight.originIATA) → \(flight.destinationIATA)",
                                      width: size.width)
        } else if let anchor = selectedAnchor, let track = selectedTrack {
            let lines = calloutLines(for: track)
            AircraftGlyph.drawCallout(&context,
                                      at: CGPoint(x: anchor.point.x, y: anchor.point.y + anchor.size + 9),
                                      title: lines.0,
                                      subtitle: lines.1,
                                      width: size.width)
        }
    }

    /// Both sides being nil would otherwise count our own aircraft as selected
    /// whenever nothing at all is.
    private var isOwnSelected: Bool {
        selectedHex != nil && selectedHex == tracker.track?.report.hex
    }

    /// Callsign on top, route underneath — "BAW117" / "LHR → JFK".
    private func calloutLines(for track: TrafficStore.Track) -> (String, String?) {
        let name = track.report.label
        if let route = routes.route(for: track.report.callsign) {
            return (route.displayNumber ?? name, route.arrow)
        }
        if routes.isLoading(track.report.callsign) { return (name, "Looking up route…") }
        return (name, nil)
    }

    /// Returns where it landed on screen, so the caller can hang a callout off
    /// it without recomputing the projection.
    @discardableResult
    private func drawOwnAircraft(_ context: inout GraphicsContext,
                                 size: CGSize,
                                 proxy: MapProxy,
                                 now: Date) -> (point: CGPoint, size: CGFloat)? {
        guard let own = ownPosition(at: now),
              let point = proxy.convert(own.coordinate, to: .local),
              point.x > -40, point.y > -40,
              point.x < size.width + 40, point.y < size.height + 40
        else { return nil }

        if let accuracy = own.accuracyMetres {
            drawAccuracyRing(&context, at: point, metres: accuracy,
                             proxy: proxy, coordinate: own.coordinate)
        }

        // A halo so the aircraft stays findable against satellite imagery.
        context.drawLayer { layer in
            layer.translateBy(x: point.x, y: point.y)
            layer.opacity = own.isStale ? 0.45 : 1
            layer.fill(Path(ellipseIn: CGRect(x: -17, y: -17, width: 34, height: 34)),
                       with: .color(Theme.accent.opacity(0.22)))
        }

        let style = TrafficSymbol(own: own.isStale)
        AircraftGlyph.draw(&context, at: point,
                           heading: own.heading,
                           hasHeading: own.hasHeading,
                           style: style,
                           isSelected: isOwnSelected)
        return (point, style.size)
    }

    private func drawAccuracyRing(_ context: inout GraphicsContext,
                                  at point: CGPoint,
                                  metres: Double,
                                  proxy: MapProxy,
                                  coordinate: CLLocationCoordinate2D) {
        let edge = GreatCircle.destination(from: coordinate, bearingDegrees: 90, distanceMetres: metres)
        guard let edgePoint = proxy.convert(edge, to: .local) else { return }
        let radius = abs(edgePoint.x - point.x)
        guard radius > 6, radius < 400 else { return }
        let rect = CGRect(x: point.x - radius, y: point.y - radius,
                          width: radius * 2, height: radius * 2)
        context.fill(Path(ellipseIn: rect), with: .color(Theme.accent.opacity(0.12)))
        context.stroke(Path(ellipseIn: rect), with: .color(Theme.accent.opacity(0.5)), lineWidth: 1)
    }

    // MARK: - Selection

    /// Nearest aircraft to the tap, within a finger's width. Hit testing lives
    /// here rather than on the symbols because they're drawn into a single
    /// `Canvas` that deliberately passes gestures through to the map.
    private func selectTrack(near point: CGPoint, proxy: MapProxy) {
        let now = Date.now
        var best: (hex: String, distance: CGFloat)?

        for track in traffic.tracks {
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
        // Resolve the route only for what the user actually asked about.
        // Prefetching every contact in view would be dozens of requests a
        // minute against a free community service for information nobody
        // looked at.
        if let hex = newSelection,
           let callsign = traffic.tracks.first(where: { $0.report.hex == hex })?.report.callsign {
            routes.lookup(callsign)
        }
    }

    private var selectedTrack: TrafficStore.Track? {
        guard let selectedHex else { return nil }
        return traffic.tracks.first { $0.report.hex == selectedHex }
    }

    // MARK: - Chrome

    private var topBar: some View {
        VStack(spacing: 8) {
            Picker("Scope", selection: $scope) {
                ForEach(Scope.allCases) { option in
                    Text(option.rawValue).tag(option)
                }
            }
            .pickerStyle(.segmented)
            .frame(maxWidth: 320)

            HStack(spacing: 6) {
                statusDot
                Text(statusText)
                if let last = traffic.lastUpdate {
                    Text("· \(Fmt.secondsAgo(last))")
                        .foregroundStyle(Theme.textSecondary)
                }
            }
            .font(.system(size: 11, weight: .bold, design: .rounded))
            .foregroundStyle(Theme.textPrimary)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(.black.opacity(0.65), in: Capsule())
        }
        .padding(.horizontal, 12)
        .padding(.top, 8)
    }

    @ViewBuilder
    private var statusDot: some View {
        switch traffic.status {
        case .idle, .loading:
            ProgressView().controlSize(.mini).tint(.white)
        case .live:
            Circle().fill(traffic.tracks.isEmpty ? Theme.orange : Theme.green)
                .frame(width: 6, height: 6)
        case .noCoverage:
            Image(systemName: "antenna.radiowaves.left.and.right.slash")
        case .failed:
            Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(Theme.orange)
        }
    }

    private var statusText: String {
        switch traffic.status {
        case .idle, .loading:
            return "Finding aircraft…"
        case .live:
            let count = traffic.tracks.count
            let airborne = traffic.tracks.filter { !$0.report.onGround }.count
            let ground = count - airborne
            if count == 0 { return "No aircraft in range" }
            return "\(airborne) airborne · \(ground) on ground"
        case .noCoverage:
            return "No ADS-B coverage here"
        case .failed(let message):
            return message
        }
    }

    private var controls: some View {
        VStack(spacing: 10) {
            controlButton(isFollowing ? "location.fill" : "location",
                          tint: isFollowing ? Theme.accent : Theme.textSecondary) {
                isFollowing.toggle()
                if isFollowing { applyCamera(animated: true) }
            }
            controlButton("plus.magnifyingglass") { zoom(by: 0.5) }
            controlButton("minus.magnifyingglass") { zoom(by: 2.0) }
        }
        .padding(.trailing, 12)
        .padding(.bottom, selectedTrack == nil ? 184 : 274)
    }

    private func controlButton(_ systemName: String,
                               tint: Color = Theme.textPrimary,
                               action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 15, weight: .bold))
                .foregroundStyle(tint)
                .frame(width: 38, height: 38)
                .background(.black.opacity(0.65), in: Circle())
        }
        .buttonStyle(.plain)
    }

    // MARK: - Bottom panel

    private var bottomPanel: some View {
        VStack(spacing: 8) {
            if let track = selectedTrack {
                selectedCard(track)
            }
            ownAircraftCard
        }
        .padding(.horizontal, 12)
        // The map deliberately runs under the safe area, so this has to clear
        // the floating tab bar by hand — otherwise the own-aircraft card is
        // half-hidden behind it.
        .padding(.bottom, 92)
    }

    private func selectedCard(_ track: TrafficStore.Track) -> some View {
        let report = track.report
        return HStack(spacing: 12) {
            Image(systemName: report.onGround ? "airplane" : "airplane.circle.fill")
                .font(.system(size: 18, weight: .bold))
                .foregroundStyle(report.onGround ? Theme.cyan : Theme.accent)
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(report.label)
                        .font(.system(size: 15, weight: .heavy, design: .rounded))
                    if let type = report.icaoType {
                        Text(type)
                            .font(Theme.monoFont(10, weight: .medium))
                            .foregroundStyle(Theme.textTertiary)
                    }
                    if report.isMLAT {
                        Text("MLAT")
                            .font(.system(size: 8, weight: .heavy, design: .rounded))
                            .foregroundStyle(Theme.orange)
                    }
                }
                routeLine(for: report)
                Text(detailLine(report))
                    .font(.system(size: 11, weight: .medium, design: .rounded))
                    .foregroundStyle(Theme.textSecondary)
            }
            Spacer()
            Button {
                withAnimation(.easeInOut(duration: 0.15)) { selectedHex = nil }
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 18))
                    .foregroundStyle(Theme.textTertiary)
            }
            .buttonStyle(.plain)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    /// Where that aircraft is headed. Held to the same standard as the
    /// positions on this map: it comes from a community route table keyed on
    /// callsign, so it says what that flight number usually flies — hence
    /// "scheduled route", not a claim about this airframe today.
    @ViewBuilder
    private func routeLine(for report: TrafficReport) -> some View {
        if let route = routes.route(for: report.callsign) {
            HStack(spacing: 6) {
                Text(route.arrow)
                    .font(.system(size: 13, weight: .heavy, design: .rounded))
                    .foregroundStyle(Theme.accent)
                if let airline = route.airlineName {
                    Text(airline)
                        .font(.system(size: 11, weight: .medium, design: .rounded))
                        .foregroundStyle(Theme.textTertiary)
                        .lineLimit(1)
                }
            }
        } else if routes.isLoading(report.callsign) {
            Text("Looking up route…")
                .font(.system(size: 11, weight: .medium, design: .rounded))
                .foregroundStyle(Theme.textTertiary)
        } else if routes.isUnknown(report.callsign) {
            Text("Route unknown")
                .font(.system(size: 11, weight: .medium, design: .rounded))
                .foregroundStyle(Theme.textTertiary)
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

    private var ownAircraftCard: some View {
        HStack(spacing: 12) {
            Image(systemName: "airplane")
                .font(.system(size: 16, weight: .bold))
                .foregroundStyle(.white)
                .rotationEffect(.degrees(-45))
            VStack(alignment: .leading, spacing: 2) {
                Text(flight.displayNumber + " · " + flight.originIATA + " → " + flight.destinationIATA)
                    .font(.system(size: 14, weight: .heavy, design: .rounded))
                    .foregroundStyle(Theme.textPrimary)
                Text(ownSummary)
                    .font(.system(size: 11, weight: .medium, design: .rounded))
                    .foregroundStyle(Theme.textSecondary)
            }
            Spacer()
            StatusPill(text: sourceLabel, color: sourceColor)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private var ownSummary: String {
        guard let own = ownPosition(at: .now) else {
            if flight.effectivePhase.isComplete { return "Arrived — showing \(flight.destinationIATA)" }
            return "Not airborne yet — showing traffic around \(flight.originIATA)"
        }
        var parts: [String] = []
        if let track = tracker.track {
            if track.report.onGround {
                parts.append(track.report.isStationary ? "At the gate" : "Taxiing")
            } else if let altitude = track.report.altitudeFeet {
                parts.append("\(Fmt.grouped(altitude)) ft")
            }
            if let speed = track.report.groundSpeedKts { parts.append("\(Int(speed)) kt") }
        } else {
            parts.append("\(Int(flight.progress(at: .now) * 100))% of the way")
            parts.append("lands \(Fmt.relative(flight.bestArrival))")
        }
        if own.isStale { parts.append("signal lost") }
        return parts.joined(separator: " · ")
    }

    private var sourceLabel: String {
        guard let own = ownPosition(at: .now) else { return "No contact" }
        if !own.isLive { return "Estimated" }
        return own.isStale ? "Stale" : "Live ADS-B"
    }

    private var sourceColor: Color {
        guard let own = ownPosition(at: .now) else { return Theme.textSecondary }
        if !own.isLive { return Theme.orange }
        return own.isStale ? Theme.orange : Theme.green
    }
}
