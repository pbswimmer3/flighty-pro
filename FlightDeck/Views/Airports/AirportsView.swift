import SwiftUI

/// Airports tab: favorites, the curated airports, and search across every
/// airport the app can place (see `AirportDatabase` for the two layers).
struct AirportsView: View {
    @EnvironmentObject private var settings: SettingsStore
    @State private var query = ""
    @State private var eventCounts: [String: Int] = [:]

    private var results: [Airport] { AirportDatabase.shared.search(query) }

    private var favorites: [Airport] {
        settings.favoriteAirports.compactMap { AirportDatabase.shared.airport(iata: $0) }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVStack(spacing: 12) {
                    if query.isEmpty && !favorites.isEmpty {
                        SectionHeader(title: "Favorites", systemImage: "star.fill")
                            .padding(.top, 4)
                        ForEach(favorites) { airport in
                            NavigationLink(value: airport) {
                                AirportRow(airport: airport,
                                           eventCount: eventCounts[airport.iata] ?? 0)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    if query.isEmpty {
                        SectionHeader(title: "Featured Airports", systemImage: "globe.americas.fill")
                            .padding(.top, favorites.isEmpty ? 4 : 10)
                    }
                    ForEach(results) { airport in
                        NavigationLink(value: airport) {
                            AirportRow(airport: airport,
                                       eventCount: eventCounts[airport.iata] ?? 0)
                        }
                        .buttonStyle(.plain)
                    }
                    if results.isEmpty && !query.isEmpty {
                        ContentUnavailableView.search(text: query)
                    }
                }
                .padding(.horizontal)
                .padding(.bottom, 24)
            }
            .background(Theme.background)
            .navigationTitle("Airports")
            .searchable(text: $query, prompt: "Search any airport by code, city, or name")
            .navigationDestination(for: Airport.self) { airport in
                AirportDetailView(airport: airport)
            }
            .task {
                // One fetch covers every US airport — badge rows that have events.
                let events = await FAAStatusService.shared.allEvents()
                var counts: [String: Int] = [:]
                for e in events { counts[e.airportIATA, default: 0] += 1 }
                eventCounts = counts
            }
        }
    }
}

struct AirportRow: View {
    let airport: Airport
    var eventCount: Int = 0

    var body: some View {
        HStack(spacing: 14) {
            Text(airport.iata)
                .scaledFont(20, weight: .heavy)
                .frame(width: 62, height: 44)
                .background(Theme.cardElevated)
                .clipShape(RoundedRectangle(cornerRadius: Theme.radiusChip, style: .continuous))
            VStack(alignment: .leading, spacing: 2) {
                Text(airport.name)
                    .scaledFont(15, weight: .bold)
                    .foregroundStyle(Theme.textPrimary)
                    .lineLimit(1)
                Text("\(airport.city), \(airport.country) · \(airport.localTimeString())")
                    .scaledFont(12, weight: .medium)
                    .monospacedDigit()
                    .foregroundStyle(Theme.textSecondary)
            }
            Spacer()
            if eventCount > 0 {
                StatusPill(text: "\(eventCount) alert\(eventCount > 1 ? "s" : "")", color: Theme.orange)
            }
            Image(systemName: "chevron.right")
                .scaledFont(12, weight: .bold, design: .default)
                .foregroundStyle(Theme.textTertiary)
                .accessibilityHidden(true)
        }
        .cardStyle(padding: 12)
        .accessibilityElement(children: .combine)
    }
}
