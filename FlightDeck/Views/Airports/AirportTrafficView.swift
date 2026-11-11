import SwiftUI
import CoreLocation

/// Live traffic at an airport. The ground scope is the interesting one: at
/// NACp 9–10 (10–30 m) the surface picture is accurate enough to read which
/// aircraft are ahead of you in the queue and roughly where on the pavement
/// they sit.
struct AirportTrafficView: View {
    let airport: Airport

    enum Scope: String, CaseIterable, Identifiable {
        case ground = "Ground"
        case nearby = "Nearby"

        var id: String { rawValue }

        var radiusNM: Int { self == .ground ? 3 : 25 }
        var spanMetres: CLLocationDistance { self == .ground ? 6_000 : 70_000 }
        /// Ten seconds for both. Ground used to poll every 3 s for the taxi
        /// queue, but queue order changes over minutes, not seconds, and 3 s
        /// spent a fifth of the app's daily adsb.lol quota (see `AdsbClient`)
        /// in five minutes of watching an apron.
        var pollInterval: TimeInterval { 10 }
    }

    @State private var scope: Scope = .ground
    @StateObject private var traffic = TrafficStore()

    private var groundTracks: [TrafficStore.Track] {
        traffic.tracks.filter(\.report.onGround)
    }

    /// Aircraft actually moving on the surface, nearest the field first.
    private var movers: [TrafficStore.Track] {
        groundTracks
            .filter { !$0.report.isStationary }
            .sorted { ($0.report.distanceNM ?? .infinity) < ($1.report.distanceNM ?? .infinity) }
    }

    private var parkedCount: Int { groundTracks.count - movers.count }

    var body: some View {
        VStack(spacing: 0) {
            LiveTrafficMapView(store: traffic,
                               center: airport.coordinate,
                               radiusNM: scope.radiusNM,
                               spanMetres: scope.spanMetres,
                               pollInterval: scope.pollInterval,
                               surface: scope == .ground ? .satellite : .standard,
                               groundOnly: scope == .ground,
                               centerLabel: airport.iata)
                .frame(maxHeight: .infinity)

            detail
        }
        .background(Theme.background)
        .navigationTitle("\(airport.iata) Traffic")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .principal) {
                Picker("Scope", selection: $scope) {
                    ForEach(Scope.allCases) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented)
                .frame(width: 190)
            }
        }
    }

    // MARK: - The readable part: what's moving on the ground

    private var detail: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                SectionHeader(title: scope == .ground ? "Moving on the ground" : "In the air nearby",
                              systemImage: scope == .ground ? "airplane.departure" : "airplane")
                if scope == .ground, parkedCount > 0 {
                    Text("\(parkedCount) parked")
                        .scaledFont(11, weight: .bold)
                        .monospacedDigit()
                        .foregroundStyle(Theme.textTertiary)
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 12)

            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(listedTracks) { track in
                        row(track)
                        Divider().overlay(Theme.separator)
                    }
                    if listedTracks.isEmpty {
                        emptyState
                    }
                    disclaimer
                    // Clear the floating tab bar.
                    Color.clear.frame(height: 60)
                }
            }
        }
        .frame(height: 260)
        .background(Theme.background)
    }

    private var listedTracks: [TrafficStore.Track] {
        scope == .ground
            ? movers
            : traffic.tracks.filter { !$0.report.onGround }
                .sorted { ($0.report.distanceNM ?? .infinity) < ($1.report.distanceNM ?? .infinity) }
    }

    private func row(_ track: TrafficStore.Track) -> some View {
        let report = track.report
        return HStack(spacing: 12) {
            Image(systemName: report.onGround ? "airplane" : "airplane.circle.fill")
                .scaledFont(15, weight: .bold, design: .default)
                .foregroundStyle(report.onGround ? Theme.cyan : Theme.accent)
                .frame(width: 24)

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(report.label)
                        .scaledFont(14, weight: .heavy)
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
                Text(subtitle(report))
                    .scaledFont(11, weight: .medium)
                    .monospacedDigit()
                    .foregroundStyle(Theme.textSecondary)
            }

            Spacer()

            if let speed = report.groundSpeedKts {
                Text("\(Int(speed)) kt")
                    .scaledFont(13, weight: .semibold, design: .monospaced)
                    .monospacedDigit()
                    .foregroundStyle(Theme.textPrimary)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 9)
        .accessibilityElement(children: .combine)
    }

    private func subtitle(_ report: TrafficReport) -> String {
        var parts: [String] = []
        if let distance = report.distanceNM {
            parts.append(String(format: "%.1f nm", distance))
        }
        if !report.onGround, let altitude = report.altitudeFeet {
            parts.append("\(altitude) ft")
        }
        if let accuracy = report.accuracyMetres {
            parts.append("±\(Int(accuracy)) m accuracy")
        }
        return parts.joined(separator: " · ")
    }

    private var emptyState: some View {
        VStack(spacing: 6) {
            Image(systemName: "antenna.radiowaves.left.and.right.slash")
                .scaledFont(22, design: .default)
                .foregroundStyle(Theme.textTertiary)
                .accessibilityHidden(true)
            Text(scope == .ground
                 ? "Nothing moving on the surface"
                 : "No aircraft in range")
                .scaledFont(14, weight: .bold)
            Text("Coverage comes from volunteer ADS-B receivers, so some airports — especially smaller or non-US fields — have gaps or no surface coverage at all.")
                .scaledFont(11, weight: .medium)
                .foregroundStyle(Theme.textSecondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(24)
    }

    private var disclaimer: some View {
        Text("Positions are estimates projected forward from the last ADS-B report. Not an air-traffic-control tool — never use it for separation or navigation.")
            .scaledFont(11, weight: .medium)
            .foregroundStyle(Theme.textTertiary)
            .multilineTextAlignment(.leading)
            .padding(16)
    }
}
