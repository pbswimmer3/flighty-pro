import SwiftUI
import MapKit

/// Map header for the flight detail screen: great-circle route line,
/// origin/destination markers, and the aircraft's position — live ADS-B when
/// available, otherwise interpolated along the route by time progress.
struct FlightMapView: View {
    let flight: Flight

    @State private var livePosition: AdsbService.Position?

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
        .task(id: flight.id) {
            await updateLivePosition()
        }
    }

    @ViewBuilder
    private func mapContent(origin: Airport, destination: Airport) -> some View {
        let routePoints = GreatCircle.points(from: origin.coordinate, to: destination.coordinate)
        let planeCoord = planeCoordinate(origin: origin, destination: destination)

        Map(initialPosition: .region(region(origin: origin, destination: destination)),
            interactionModes: [.pan, .zoom]) {

            MapPolyline(coordinates: routePoints)
                .stroke(Theme.accent, style: StrokeStyle(lineWidth: 2.5, dash: [6, 5]))

            Annotation(origin.iata, coordinate: origin.coordinate) {
                airportDot
            }
            Annotation(destination.iata, coordinate: destination.coordinate) {
                airportDot
            }

            if let planeCoord, flight.effectivePhase.isAirborne {
                Annotation("", coordinate: planeCoord) {
                    planeMarker(origin: origin, destination: destination, at: planeCoord)
                }
            }
        }
        .mapStyle(.standard(elevation: .flat, pointsOfInterest: .excludingAll))
    }

    private var airportDot: some View {
        Circle()
            .fill(Theme.accent)
            .frame(width: 10, height: 10)
            .overlay(Circle().stroke(.white, lineWidth: 2))
    }

    private func planeMarker(origin: Airport, destination: Airport,
                             at coord: CLLocationCoordinate2D) -> some View {
        let heading = livePosition?.trackDegrees
            ?? GreatCircle.bearing(from: coord, to: destination.coordinate)
        return Image(systemName: "airplane")
            .font(.system(size: 22, weight: .bold))
            .foregroundStyle(.white)
            .shadow(color: .black.opacity(0.8), radius: 3)
            .rotationEffect(.degrees(heading - 90))  // SF Symbol plane points right (90°)
    }

    private func planeCoordinate(origin: Airport, destination: Airport) -> CLLocationCoordinate2D? {
        if let live = livePosition { return live.coordinate }
        guard flight.effectivePhase.isAirborne else { return nil }
        return GreatCircle.intermediatePoint(from: origin.coordinate,
                                             to: destination.coordinate,
                                             fraction: flight.progress)
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

    private func updateLivePosition() async {
        guard flight.effectivePhase.isAirborne, flight.isLiveData,
              let callSign = flight.callSign else { return }
        livePosition = await AdsbService.shared.position(callSign: callSign)
    }
}
