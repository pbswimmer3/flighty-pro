import SwiftUI
import MapKit

/// Map header for the flight detail screen: great-circle route line,
/// origin/destination markers, and the aircraft.
///
/// The plane is drawn in a `Canvas` driven by a display-linked clock rather
/// than as a MapKit annotation bound to received positions. With a live ADS-B
/// track it dead-reckons between samples and eases onto each new fix; without
/// one it advances continuously along the route as the flight clock runs.
/// Either way it never jumps.
struct FlightMapView: View {
    let flight: Flight
    @ObservedObject var tracker: AircraftTracker

    @Environment(\.scenePhase) private var scenePhase

    private var origin: Airport? { AirportDatabase.shared.airport(iata: flight.originIATA) }
    private var destination: Airport? { AirportDatabase.shared.airport(iata: flight.destinationIATA) }

    var body: some View {
        Group {
            if let origin, let destination {
                mapContent(origin: origin, destination: destination)
            } else {
                // Unknown airport (not in bundled DB) — skip the map gracefully.
                ZStack {
                    Theme.card
                    Label("Route map unavailable", systemImage: "map")
                        .foregroundStyle(Theme.textSecondary)
                }
            }
        }
        .onAppear { startTracking() }
        .onDisappear { tracker.stop() }
        .onChange(of: flight.id) { _, _ in startTracking() }
        .onChange(of: scenePhase) { _, phase in
            phase == .active ? startTracking() : tracker.stop()
        }
    }

    /// Live position is only worth polling for a real flight that's actually
    /// flying — demo flights have no airframe to find.
    private func startTracking() {
        guard flight.isLiveData, flight.isActive, let callSign = flight.callSign else {
            tracker.stop()
            return
        }
        tracker.start(callSign: callSign, interval: 5)
    }

    @ViewBuilder
    private func mapContent(origin: Airport, destination: Airport) -> some View {
        MapReader { proxy in
            Map(initialPosition: .region(region(origin: origin, destination: destination)),
                interactionModes: [.pan, .zoom]) {

                MapPolyline(coordinates: GreatCircle.points(from: origin.coordinate,
                                                            to: destination.coordinate))
                    .stroke(Theme.accent, style: StrokeStyle(lineWidth: 2.5, dash: [6, 5]))

                Annotation(origin.iata, coordinate: origin.coordinate) { airportDot }
                Annotation(destination.iata, coordinate: destination.coordinate) { airportDot }
            }
            .mapStyle(.standard(elevation: .flat, pointsOfInterest: .excludingAll))
            .overlay {
                TimelineView(.animation(minimumInterval: frameInterval,
                                        paused: scenePhase != .active)) { timeline in
                    Canvas { context, size in
                        drawAircraft(&context, size: size, proxy: proxy,
                                     origin: origin, destination: destination,
                                     now: timeline.date)
                    }
                }
                .allowsHitTesting(false)
            }
            .overlay(alignment: .topTrailing) { sourceBadge }
        }
    }

    private var frameInterval: Double? {
        ProcessInfo.processInfo.isLowPowerModeEnabled ? 1.0 / 30.0 : nil
    }

    private var airportDot: some View {
        Circle()
            .fill(Theme.accent)
            .frame(width: 10, height: 10)
            .overlay(Circle().stroke(.white, lineWidth: 2))
    }

    // MARK: - Where the plane is right now

    private struct Placement {
        var coordinate: CLLocationCoordinate2D
        var heading: Double
        var isLive: Bool
        var isStale: Bool
    }

    private func placement(origin: Airport, destination: Airport, at now: Date) -> Placement? {
        if let track = tracker.track {
            let rendered = track.state(at: now)
            // Surface aircraft report true_heading, airborne ones report track;
            // if neither is present, point along the route instead of claiming
            // a heading we don't have.
            let heading = track.report.headingDegrees == nil
                ? GreatCircle.bearing(from: rendered.coordinate, to: destination.coordinate)
                : rendered.headingDegrees
            return Placement(coordinate: rendered.coordinate,
                             heading: heading,
                             isLive: true,
                             isStale: rendered.isStale)
        }

        guard flight.effectivePhase.isAirborne else { return nil }
        let fraction = flight.progress(at: now)
        let coordinate = GreatCircle.intermediatePoint(from: origin.coordinate,
                                                       to: destination.coordinate,
                                                       fraction: fraction)
        // Face along the route by sampling just ahead; at the very end fall
        // back to bearing straight at the destination.
        let ahead = GreatCircle.intermediatePoint(from: origin.coordinate,
                                                  to: destination.coordinate,
                                                  fraction: min(fraction + 0.005, 1))
        let heading = fraction >= 0.995
            ? GreatCircle.bearing(from: coordinate, to: destination.coordinate)
            : GreatCircle.bearing(from: coordinate, to: ahead)
        return Placement(coordinate: coordinate, heading: heading, isLive: false, isStale: false)
    }

    private func drawAircraft(_ context: inout GraphicsContext,
                              size: CGSize,
                              proxy: MapProxy,
                              origin: Airport,
                              destination: Airport,
                              now: Date) {
        guard let placement = placement(origin: origin, destination: destination, at: now),
              let point = proxy.convert(placement.coordinate, to: .local),
              point.x > -30, point.y > -30,
              point.x < size.width + 30, point.y < size.height + 30
        else { return }

        context.drawLayer { layer in
            layer.translateBy(x: point.x, y: point.y)
            layer.opacity = placement.isStale ? 0.4 : 1

            // Soft halo so the icon reads against both land and sea.
            let halo = CGRect(x: -16, y: -16, width: 32, height: 32)
            layer.fill(Path(ellipseIn: halo), with: .color(Theme.accent.opacity(0.22)))

            layer.rotate(by: .degrees(placement.heading))
            var path = Path()
            let s: CGFloat = 12
            path.move(to: CGPoint(x: 0, y: -s))
            path.addLine(to: CGPoint(x: s * 0.62, y: s * 0.75))
            path.addLine(to: CGPoint(x: 0, y: s * 0.35))
            path.addLine(to: CGPoint(x: -s * 0.62, y: s * 0.75))
            path.closeSubpath()
            layer.fill(path, with: .color(.white))
            layer.stroke(path, with: .color(.black.opacity(0.6)), lineWidth: 1)
        }
    }

    // MARK: - Honesty about the source

    @ViewBuilder
    private var sourceBadge: some View {
        if let label = badgeLabel {
            Text(label)
                .font(.system(size: 10, weight: .bold, design: .rounded))
                .foregroundStyle(Theme.textPrimary)
                .padding(.horizontal, 8)
                .padding(.vertical, 5)
                .background(.black.opacity(0.6), in: Capsule())
                .padding(10)
        }
    }

    private var badgeLabel: String? {
        if let track = tracker.track {
            let age = Date.now.timeIntervalSince(track.measured.validAt)
            if age > DeadReckoning.Limits.staleAfter { return "ADS-B · signal lost" }
            return "LIVE ADS-B · \(Fmt.secondsAgo(track.measured.validAt))"
        }
        if tracker.isSearching { return "Searching ADS-B…" }
        if flight.effectivePhase.isAirborne { return "Estimated position" }
        return nil
    }

    private func region(origin: Airport, destination: Airport) -> MKCoordinateRegion {
        let midLat = (origin.lat + destination.lat) / 2
        let midLon = (origin.lon + destination.lon) / 2
        let latDelta = max(abs(origin.lat - destination.lat) * 1.6, 4)
        let lonDelta = max(abs(origin.lon - destination.lon) * 1.6, 4)
        return MKCoordinateRegion(
            center: CLLocationCoordinate2D(latitude: midLat, longitude: midLon),
            span: MKCoordinateSpan(latitudeDelta: min(latDelta, 140),
                                   longitudeDelta: min(lonDelta, 300)))
    }
}
