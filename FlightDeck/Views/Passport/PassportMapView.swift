import SwiftUI
import MapKit

/// Every flight you've taken, drawn at once.
///
/// Routes are weighted by how often you've flown them — the commute you do
/// forty times a year should be visibly heavier than the one holiday to Lisbon,
/// which is the whole point of looking at the map instead of the list.
struct PassportMapView: View {
    let stats: PassportStats
    var interactive = true

    @State private var camera: MapCameraPosition = .automatic

    private struct DrawnRoute: Identifiable {
        var id: String
        var coordinates: [CLLocationCoordinate2D]
        var weight: Double        // 0…1 relative to the most-flown route
        var count: Int
    }

    private var drawnRoutes: [DrawnRoute] {
        let peak = Double(stats.routes.first?.count ?? 1)
        return stats.routes.compactMap { route in
            guard let origin = AirportDatabase.shared.airport(iata: route.origin),
                  let destination = AirportDatabase.shared.airport(iata: route.destination)
            else { return nil }
            return DrawnRoute(
                id: route.id,
                coordinates: GreatCircle.points(from: origin.coordinate,
                                                to: destination.coordinate,
                                                count: 48),
                weight: peak <= 0 ? 0 : Double(route.count) / peak,
                count: route.count)
        }
    }

    private var visitedAirports: [Airport] {
        stats.airports.compactMap { AirportDatabase.shared.airport(iata: $0.key) }
    }

    /// Counts keyed by IATA so a dot's size can reflect how often you've been
    /// through it without a second lookup per annotation.
    private var visitCounts: [String: Int] {
        Dictionary(stats.airports.map { ($0.key, $0.count) }, uniquingKeysWith: { a, _ in a })
    }

    private var peakVisits: Int { max(stats.airports.first?.count ?? 1, 1) }

    var body: some View {
        Map(position: $camera, interactionModes: interactive ? [.pan, .zoom] : []) {
            ForEach(drawnRoutes) { route in
                MapPolyline(coordinates: route.coordinates)
                    .stroke(Theme.accent.opacity(0.35 + 0.5 * route.weight),
                            style: StrokeStyle(lineWidth: 1 + 3.5 * route.weight,
                                               lineCap: .round,
                                               lineJoin: .round))
            }
            ForEach(visitedAirports) { airport in
                Annotation(airport.iata, coordinate: airport.coordinate) {
                    let visits = visitCounts[airport.iata] ?? 1
                    let size = 6 + 6 * (Double(visits) / Double(peakVisits))
                    Circle()
                        .fill(Theme.cyan)
                        .frame(width: size, height: size)
                        .overlay(Circle().stroke(.white.opacity(0.9), lineWidth: 1))
                }
                .annotationTitles(.hidden)
            }
        }
        .mapStyle(.standard(elevation: .flat, pointsOfInterest: .excludingAll))
        .onAppear { camera = .automatic }
    }
}

/// The map plus its headline counts, as it appears on the Passport page.
struct PassportMapCard: View {
    let stats: PassportStats

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionHeader(title: "Where You've Been", systemImage: "globe.americas.fill")

            PassportMapView(stats: stats)
                .frame(height: 240)
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                .overlay(alignment: .bottomTrailing) {
                    Text("Line weight = how often you fly it")
                        .font(.system(size: 9, weight: .semibold, design: .rounded))
                        .foregroundStyle(Theme.textSecondary)
                        .padding(.horizontal, 7)
                        .padding(.vertical, 4)
                        .background(.black.opacity(0.6), in: Capsule())
                        .padding(8)
                }

            HStack(spacing: 0) {
                StatBlock(caption: "Airports", value: "\(stats.airports.count)")
                StatBlock(caption: "Countries", value: "\(stats.countries.count)", color: Theme.cyan)
                StatBlock(caption: "Routes", value: "\(stats.routes.count)")
            }

            if !stats.unresolvedAirports.isEmpty {
                Text("Not on the map: \(stats.unresolvedAirports.joined(separator: ", ")) — outside the bundled airport database, so their distance isn't counted either.")
                    .font(.system(size: 11, weight: .medium, design: .rounded))
                    .foregroundStyle(Theme.textTertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .cardStyle()
    }
}
