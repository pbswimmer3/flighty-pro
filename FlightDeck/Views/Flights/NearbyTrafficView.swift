import SwiftUI
import CoreLocation

/// Traffic around the user's own aircraft, with their airframe highlighted and
/// its NACp confidence ring drawn — the one target where the accuracy circle
/// is information rather than clutter.
struct NearbyTrafficView: View {
    let flight: Flight
    @ObservedObject var tracker: AircraftTracker

    /// Where the radius search is anchored. Follows the aircraft, but only in
    /// jumps: re-querying on every position update would poll far harder than
    /// the budget allows for no extra information.
    @State private var queryCenter: CLLocationCoordinate2D
    @StateObject private var traffic = TrafficStore()

    private let recenterThresholdNM: Double = 8
    private let radiusNM = 25

    init(flight: Flight, tracker: AircraftTracker) {
        self.flight = flight
        self.tracker = tracker
        let start = tracker.track?.report.coordinate
            ?? AirportDatabase.shared.airport(iata: flight.destinationIATA)?.coordinate
            ?? CLLocationCoordinate2D(latitude: 0, longitude: 0)
        _queryCenter = State(initialValue: start)
    }

    var body: some View {
        LiveTrafficMapView(store: traffic,
                           center: queryCenter,
                           radiusNM: radiusNM,
                           spanMetres: 90_000,
                           pollInterval: 5,
                           surface: .standard,
                           groundOnly: false,
                           highlightHex: tracker.track?.report.hex,
                           centerLabel: nil)
            .ignoresSafeArea(edges: .bottom)
            .navigationTitle("Traffic near \(flight.displayNumber)")
            .navigationBarTitleDisplayMode(.inline)
            .onChange(of: tracker.track?.report.coordinate.latitude) { _, _ in
                recenterIfDrifted()
            }
    }

    private func recenterIfDrifted() {
        guard let coordinate = tracker.track?.report.coordinate else { return }
        let driftNM = GreatCircle.distanceMiles(from: queryCenter, to: coordinate) / 1.15078
        if driftNM > recenterThresholdNM {
            queryCenter = coordinate
        }
    }
}
