import SwiftUI

/// Airports tab: favorites + searchable list of the bundled airport database.
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
                        SectionHeader(title: "All Airports", systemImage: "globe.americas.fill")
                            .padding(.top, 10)
                    }
                    ForEach(results) { airport in
                        NavigationLink(value: airport) {
                            AirportRow(airport: airport,
                                       eventCount: eventCounts[airport.iata] ?? 0)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal)
                .padding(.bottom, 24)
            }
            .background(Theme.background)
            .navigationTitle("Airports")
            .searchable(text: $query, prompt: "Search by code, city, or name")
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
                .font(Theme.codeFont(20))
                .frame(width: 62, height: 44)
                .background(Theme.cardElevated)
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            VStack(alignment: .leading, spacing: 2) {
                Text(airport.name)
                    .font(.system(size: 15, weight: .bold, design: .rounded))
                    .foregroundStyle(Theme.textPrimary)
                    .lineLimit(1)
                Text("\(airport.city), \(airport.country) · \(airport.localTimeString())")
                    .font(.system(size: 12, weight: .medium, design: .rounded))
                    .foregroundStyle(Theme.textSecondary)
            }
            Spacer()
            if eventCount > 0 {
                StatusPill(text: "\(eventCount) alert\(eventCount > 1 ? "s" : "")", color: Theme.orange)
            }
            Image(systemName: "chevron.right")
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(Theme.textTertiary)
        }
        .cardStyle(padding: 12)
    }
}
