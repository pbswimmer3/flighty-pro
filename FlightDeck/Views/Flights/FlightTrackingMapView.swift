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
        /// the response is small and every contact is genuinely "around you".
        var radiusNM: Int {
            switch self {
            case .ground: return 5
            case .nearby: return 40
            case .route: return 90
            }
        }

        /// This screen's ceiling; `AdsbClient` stretches it further as the
        /// day's adsb.lol quota runs down. Ten seconds is plenty with dead
        /// reckoning in between — it was 3 s and 5 s, which with the own-
        /// aircraft poll on top spent the whole daily quota in ~20 minutes.
        /// Route is a continental picture that barely moves at that zoom.
        var pollInterval: TimeInterval { self == .route ? 30 : 10 }

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

    /// `initialScope` overrides the airborne/ground choice below; `nil` (the
    /// default, and what the flight page passes) keeps that choice. It exists
    /// so the screenshot harness can open on the whole route.
    init(flight: Flight, tracker: AircraftTracker, initialScope: Scope? = nil) {
        self.flight = flight
        self.tracker = tracker

        // Airborne opens on the wider picture; on the ground the interesting
        // detail is the apron you're sitting on.
        let startScope: Scope = initialScope
            ?? (flight.effectivePhase.isAirborne ? .nearby : .ground)
        _scope = State(initialValue: startScope)
        _cameraDistance = State(initialValue: startScope.cameraDistance)

        let anchor = tracker.track?.report.coordinate
            ?? Self.parkedAirport(for: flight)?.coordinate
            ?? CLLocationCoordinate2D(latitude: 0, longitude: 0)
        _queryCenter = State(initialValue: anchor)
        _camera = State(initialValue: .camera(MapCamera(centerCoordinate: anchor,
                                                        distance: startScope.cameraDistance,
                                                        heading: 0,
                                                        pitch: 0)))
    }

    // MARK: - Geometry

    private var origin: Airport? { AirportDatabase.shared.airport(iata: flight.originIATA) }
    private var destination: Airport? { AirportDatabase.shared.airport(iata: flight.destinationIATA) }

    /// The airport the map sits on when there's no aircraft position to follow:
    /// the destination once the flight is down, the origin otherwise, and the
    /// other end only if the one we want can't be placed.
    ///
    /// This is the single answer to "which field is on screen", shared by the
    /// camera, the traffic search, the caption and the flight page's button.
    /// They used to work it out separately, and when SNA was missing from the
    /// airport database the camera fell through to SFO while the caption still
    /// read "showing traffic around SNA".
    static func parkedAirport(for flight: Flight) -> Airport? {
        let db = AirportDatabase.shared
        let origin = db.airport(iata: flight.originIATA)
        let destination = db.airport(iata: flight.destinationIATA)
        return flight.effectivePhase.isComplete ? (destination ?? origin) : (origin ?? destination)
    }

    private var parkedAirport: Airport? { Self.parkedAirport(for: flight) }

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
        return parkedAirport?.coordinate ?? queryCenter
    }

    /// False only when there's no live fix and neither airport can be placed.
    /// Then there is nothing honest to centre on, and polling traffic around
    /// 0°N 0°E would caption the Gulf of Guinea as if it were the user's field.
    private var canAnchor: Bool {
        tracker.track != nil || parkedAirport != nil
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
            // Every aircraft is drawn in a Canvas VoiceOver can't see; speak
            // the same summary the pill and the card show instead.
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Live map. \(statusText). \(ownSummary)")
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
            tracker.setVisible(true, on: "trackingMap")
            startTrackingOwnAircraft()
        }
        .onDisappear {
            traffic.stop()
            tracker.setVisible(false, on: "trackingMap")
        }
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
        // re-anchoring the radius search: every ten to fifteen seconds, and
        // never faster than the data actually changes.
        .onChange(of: tracker.track?.measured.validAt) { _, _ in
            recenterIfDrifted()
            if isFollowing { applyCamera(animated: true) }
        }
        // Without an ADS-B contact there are no fixes to key off, so the poll
        // itself provides the cadence — the estimated position still moves, and
        // both the camera and the search radius have to move with it.
        .onChange(of: traffic.lastUpdate) { _, _ in
            feedOwnAircraftFromTraffic()
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
        guard canAnchor else { traffic.stop(); return }
        traffic.start(near: queryCenter, radiusNM: scope.radiusNM, interval: scope.pollInterval)
    }

    /// The flight page normally has the tracker running already; this covers
    /// coming back from the background, where it was deliberately stopped.
    private func startTrackingOwnAircraft() {
        guard flight.isLiveData, flight.isActive, let callSign = flight.callSign else { return }
        tracker.start(callSign: callSign)
    }

    /// The radius search is centred on the user's aircraft, so it nearly
    /// always contains it. Handing that report to the tracker means the
    /// separate by-callsign request is skipped — it used to double this
    /// screen's adsb.lol traffic for the same data.
    ///
    /// Matched by hex once the tracker knows the airframe; by callsign only
    /// before then, so another leg's aircraft sharing the flight number can't
    /// take over a track that's already locked on.
    private func feedOwnAircraftFromTraffic() {
        guard flight.isLiveData, flight.isActive, let updated = traffic.lastUpdate else { return }
        let candidate: TrafficStore.Track?
        if let hex = tracker.track?.report.hex {
            candidate = traffic.tracks.first { $0.report.hex == hex }
        } else if let callSign = flight.callSign?.trimmingCharacters(in: .whitespaces).uppercased(),
                  !callSign.isEmpty {
            candidate = traffic.tracks.first { $0.report.callsign?.uppercased() == callSign }
        } else {
            candidate = nil
        }
        // Only if it was in *this* response: tracks linger a few seconds after
        // they vanish, and a lingering one would keep the tracker from asking.
        guard let own = candidate,
              abs(own.lastReportAt.timeIntervalSince(updated)) < 1 else { return }
        tracker.ingest(own.report)
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
                               heading: screenHeading(rendered.headingDegrees,
                                                      at: rendered.coordinate, point: point, proxy: proxy),
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

    /// Callsign on top, route underneath — "BAW117" / "LHR → JFK", or
    /// "Arriving SFO" when the schedule is visibly the other leg.
    private func calloutLines(for track: TrafficStore.Track) -> (String, String?) {
        let name = track.report.label
        if let route = routes.route(for: track.report.callsign) {
            return (route.displayNumber ?? name, RouteLabel(route: route, report: track.report).headline)
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
                           heading: screenHeading(own.heading,
                                                  at: own.coordinate, point: point, proxy: proxy),
                           hasHeading: own.hasHeading,
                           style: style,
                           isSelected: isOwnSelected)
        return (point, style.size)
    }

    /// A true-north heading turned into the angle to draw on screen.
    ///
    /// The canvas is screen-space, but the map can be rotated (the compass
    /// button, or a two-finger twist), and then "up" is no longer north — a
    /// glyph rotated by the raw heading points the wrong way on a rotated map.
    /// Projecting a point a little way along the heading and measuring the
    /// screen angle folds in the map's rotation without tracking camera state.
    private func screenHeading(_ heading: Double,
                               at coordinate: CLLocationCoordinate2D,
                               point: CGPoint,
                               proxy: MapProxy) -> Double {
        let ahead = GreatCircle.destination(from: coordinate, bearingDegrees: heading, distanceMetres: 1_000)
        guard let aheadPoint = proxy.convert(ahead, to: .local) else { return heading }
        let dx = aheadPoint.x - point.x
        let dy = aheadPoint.y - point.y
        guard hypot(dx, dy) > 0.01 else { return heading }
        return atan2(dx, -dy) * 180 / .pi
    }

    private func drawAccuracyRing(_ context: inout GraphicsContext,
                                  at point: CGPoint,
                                  metres: Double,
                                  proxy: MapProxy,
                                  coordinate: CLLocationCoordinate2D) {
        let edge = GreatCircle.destination(from: coordinate, bearingDegrees: 90, distanceMetres: metres)
        guard let edgePoint = proxy.convert(edge, to: .local) else { return }
        let radius = hypot(edgePoint.x - point.x, edgePoint.y - point.y)
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
        if let hex = newSelection, hex != tracker.track?.report.hex,
           let callsign = traffic.tracks.first(where: { $0.report.hex == hex })?.report.callsign {
            routes.lookup(callsign)
        }
    }

    /// The tapped *other* aircraft. Our own aircraft is in `traffic.tracks`
    /// too, but it's described by the user's flight (callout and
    /// `ownAircraftCard`), never by a callsign lookup: the route table holds
    /// one leg per flight number, so it can name the other leg of the user's
    /// own rotation — "QXE2187 SFO → LAX" on a plane landing at SFO.
    private var selectedTrack: TrafficStore.Track? {
        guard let selectedHex, !isOwnSelected else { return nil }
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
            .scaledFont(11, weight: .bold)
            .monospacedDigit()
            .foregroundStyle(Theme.textPrimary)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(.black.opacity(0.65), in: Capsule())
            .accessibilityElement(children: .combine)
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
            // The rate-limit text says when it retries and is worth showing;
            // "adsb.lol returned HTTP 503" is not something to put in front
            // of a traveller.
            return message.localizedCaseInsensitiveContains("retrying")
                ? message : "Live traffic unavailable right now"
        }
    }

    private var controls: some View {
        VStack(spacing: 10) {
            controlButton(isFollowing ? "location.fill" : "location",
                          label: isFollowing ? "Stop following" : "Follow aircraft",
                          tint: isFollowing ? Theme.accent : Theme.textSecondary) {
                isFollowing.toggle()
                if isFollowing { applyCamera(animated: true) }
            }
            controlButton("plus.magnifyingglass", label: "Zoom in") { zoom(by: 0.5) }
            controlButton("minus.magnifyingglass", label: "Zoom out") { zoom(by: 2.0) }
        }
        .padding(.trailing, 12)
        .padding(.bottom, selectedTrack == nil ? 184 : 274)
    }

    private func controlButton(_ systemName: String,
                               label: String,
                               tint: Color = Theme.textPrimary,
                               action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemName)
                .scaledFont(15, weight: .bold, design: .default)
                .foregroundStyle(tint)
                .frame(width: 44, height: 44)
                .background(.black.opacity(0.65), in: Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
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
                .scaledFont(18, weight: .bold, design: .default)
                .foregroundStyle(report.onGround ? Theme.cyan : Theme.accent)
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(report.label)
                        .scaledFont(15, weight: .heavy)
                    if let type = report.icaoType {
                        Text(type)
                            .scaledFont(11, weight: .medium, design: .monospaced)
                            .foregroundStyle(Theme.textTertiary)
                    }
                    if report.isMLAT {
                        Text("MLAT")
                            .scaledFont(11, weight: .heavy)
                            .foregroundStyle(Theme.orange)
                    }
                }
                routeLine(for: report)
                Text(detailLine(track))
                    .scaledFont(11, weight: .medium)
                    .monospacedDigit()
                    .foregroundStyle(Theme.textSecondary)
            }
            Spacer()
            Button {
                withAnimation(.easeInOut(duration: 0.15)) { selectedHex = nil }
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .scaledFont(18, design: .default)
                    .foregroundStyle(Theme.textTertiary)
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Dismiss")
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    /// Where that aircraft is headed. Held to the same standard as the
    /// positions on this map: it comes from a community route table keyed on
    /// callsign, so it says what that flight number usually flies — hence
    /// "scheduled route", not a claim about this airframe today. When the
    /// aircraft is visibly flying the other leg, `RouteLabel` leads with that.
    @ViewBuilder
    private func routeLine(for report: TrafficReport) -> some View {
        if let route = routes.route(for: report.callsign) {
            let label = RouteLabel(route: route, report: report)
            VStack(alignment: .leading, spacing: 1) {
                HStack(spacing: 6) {
                    Text(label.headline)
                        .scaledFont(13, weight: .heavy)
                        .foregroundStyle(Theme.accent)
                    if let airline = route.airlineName {
                        Text(airline)
                            .scaledFont(11, weight: .medium)
                            .foregroundStyle(Theme.textTertiary)
                            .lineLimit(1)
                    }
                }
                Text(label.note)
                    .scaledFont(11, weight: .medium)
                    .foregroundStyle(label.contradictsSchedule ? Theme.orange : Theme.textTertiary)
            }
        } else if routes.isLoading(report.callsign) {
            Text("Looking up route…")
                .scaledFont(11, weight: .medium)
                .foregroundStyle(Theme.textTertiary)
        } else if routes.isUnknown(report.callsign) {
            Text("Route unknown")
                .scaledFont(11, weight: .medium)
                .foregroundStyle(Theme.textTertiary)
        }
    }

    private func detailLine(_ track: TrafficStore.Track) -> String {
        let report = track.report
        var parts: [String] = []
        if report.onGround {
            parts.append(report.isStationary ? "Parked" : "Taxiing")
        } else if let altitude = report.altitudeFeet {
            parts.append("\(Fmt.grouped(altitude)) ft")
        }
        if let speed = report.groundSpeedKts { parts.append("\(Int(speed)) kt") }
        if let distance = distanceText(to: track) { parts.append(distance) }
        if let registration = report.registration, registration != report.label {
            parts.append(registration)
        }
        return parts.isEmpty ? "Live ADS-B contact" : parts.joined(separator: " · ")
    }

    /// How far the contact is from the user's aircraft, or — with no aircraft
    /// to measure from — from the airport the map is parked on. Both ends are
    /// the positions drawn on screen, so the number matches what you see.
    ///
    /// Deliberately not adsb.lol's `dst`. That's measured from the search
    /// centre, which follows the aircraft only in jumps of up to a third of
    /// the radius (`recenterThresholdNM`): it read "12.1 nm away" for a
    /// Cessna about 7 nm from the user's own aircraft, on the card the user
    /// was reading while asking whether the map was right (#14).
    private func distanceText(to track: TrafficStore.Track) -> String? {
        let now = Date.now
        let contact = track.state(at: now).coordinate
        if let own = ownPosition(at: now) {
            return "\(Self.nauticalMiles(from: own.coordinate, to: contact)) nm from \(flight.displayNumber)"
        }
        if let parked = parkedAirport {
            return "\(Self.nauticalMiles(from: parked.coordinate, to: contact)) nm from \(parked.iata)"
        }
        return track.report.distanceNM.map { String(format: "%.1f nm away", $0) }
    }

    private static func nauticalMiles(from a: CLLocationCoordinate2D, to b: CLLocationCoordinate2D) -> String {
        String(format: "%.1f", GreatCircle.distanceMiles(from: a, to: b) / 1.15078)
    }

    private var ownAircraftCard: some View {
        HStack(spacing: 12) {
            Image(systemName: "airplane")
                .scaledFont(16, weight: .bold, design: .default)
                .foregroundStyle(.white)
                .rotationEffect(.degrees(-45))
            VStack(alignment: .leading, spacing: 2) {
                Text(flight.displayNumber + " · " + flight.originIATA + " → " + flight.destinationIATA)
                    .scaledFont(14, weight: .heavy)
                    .foregroundStyle(Theme.textPrimary)
                Text(ownSummary)
                    .scaledFont(11, weight: .medium)
                    .monospacedDigit()
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
        guard let own = ownPosition(at: .now) else { return parkedSummary }
        var parts: [String] = []
        if let track = tracker.track {
            if track.report.onGround {
                parts.append(track.report.isStationary ? "At the gate" : "Taxiing")
            } else if let altitude = track.report.altitudeFeet {
                parts.append("\(Fmt.grouped(altitude)) ft")
            }
            if let speed = track.report.groundSpeedKts { parts.append("\(Int(speed)) kt") }
        } else {
            // A sample or hand-entered flight has no airframe to find, so the
            // real traffic around it is around a plane that isn't there.
            if !flight.isLiveData { parts.append("Not a live flight — placed from the schedule") }
            parts.append("\(Int(flight.progress(at: .now) * 100))% of the way")
            parts.append("lands \(Fmt.relative(flight.bestArrival))")
        }
        if own.isStale { parts.append("signal lost") }
        return parts.joined(separator: " · ")
    }

    /// What the map is showing when it isn't following the aircraft. Names the
    /// airport actually on screen — `parkedAirport` — never the one we wished
    /// we could show.
    private var parkedSummary: String {
        let phase = flight.effectivePhase
        guard let parked = parkedAirport else {
            return "Can't place \(flight.originIATA) or \(flight.destinationIATA) on the map"
        }
        let showing = "showing traffic around \(parked.iata)"
        if phase.isAirborne { return "No ADS-B contact yet — \(showing)" }
        let wanted = (phase.isComplete ? flight.destinationIATA : flight.originIATA).uppercased()
        if parked.iata != wanted { return "Can't place \(wanted) on the map — \(showing) instead" }
        return phase.isComplete ? "Arrived — \(showing)" : "Not airborne yet — \(showing)"
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
