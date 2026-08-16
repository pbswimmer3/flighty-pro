import SwiftUI

/// Every flight that's already happened, grouped by month and searchable.
///
/// Nothing puts flights here by hand: `FlightStore.pastFlights` archives them
/// automatically 30 minutes after landing (`Flight.archivesAt`).
struct PastFlightsView: View {
    @EnvironmentObject private var store: FlightStore
    @State private var query = ""

    private struct MonthGroup: Identifiable {
        var id: String
        var title: String
        var flights: [Flight]
    }

    private var filtered: [Flight] {
        let trimmed = query.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return store.pastFlights }
        return store.pastFlights.filter { flight in
            flight.displayNumber.localizedCaseInsensitiveContains(trimmed)
                || flight.airlineName.localizedCaseInsensitiveContains(trimmed)
                || flight.originIATA.localizedCaseInsensitiveContains(trimmed)
                || flight.destinationIATA.localizedCaseInsensitiveContains(trimmed)
                || (flight.aircraftType?.localizedCaseInsensitiveContains(trimmed) ?? false)
                || (flight.tailNumber?.localizedCaseInsensitiveContains(trimmed) ?? false)
        }
    }

    /// Grouped newest month first. The key is year-month so December and
    /// January of different years never collapse together.
    private var groups: [MonthGroup] {
        var order: [String] = []
        var buckets: [String: [Flight]] = [:]
        var titles: [String: String] = [:]

        for flight in filtered {
            let calendar = flight.originCalendar
            let components = calendar.dateComponents([.year, .month], from: flight.bestDeparture)
            let key = String(format: "%04d-%02d", components.year ?? 0, components.month ?? 0)
            if buckets[key] == nil {
                order.append(key)
                titles[key] = Fmt.monthAndYear(flight.bestDeparture, tz: flight.originAirport?.timeZone)
            }
            buckets[key, default: []].append(flight)
        }

        return order.map { MonthGroup(id: $0, title: titles[$0] ?? $0, flights: buckets[$0] ?? []) }
    }

    var body: some View {
        ScrollView {
            LazyVStack(spacing: 14, pinnedViews: [.sectionHeaders]) {
                if store.pastFlights.isEmpty {
                    emptyState
                } else if filtered.isEmpty {
                    noResults
                } else {
                    ForEach(groups) { group in
                        Section {
                            ForEach(group.flights) { flight in
                                NavigationLink(value: flight) {
                                    PastFlightRow(flight: flight)
                                }
                                .buttonStyle(.plain)
                                .contextMenu {
                                    Button(role: .destructive) {
                                        store.remove(flight)
                                    } label: {
                                        Label("Remove Flight", systemImage: "trash")
                                    }
                                }
                            }
                        } header: {
                            HStack {
                                Text(group.title)
                                    .font(.system(size: 13, weight: .heavy, design: .rounded))
                                    .foregroundStyle(Theme.textSecondary)
                                Spacer()
                                Text("\(group.flights.count)")
                                    .font(Theme.monoFont(12))
                                    .foregroundStyle(Theme.textTertiary)
                            }
                            .padding(.horizontal, 4)
                            .padding(.vertical, 8)
                            .background(Theme.background)
                        }
                    }
                }
            }
            .padding(.horizontal)
            .padding(.bottom, 30)
        }
        .background(Theme.background)
        .navigationTitle("Past Flights")
        .navigationBarTitleDisplayMode(.inline)
        .searchable(text: $query, prompt: "Flight, airport, airline or tail number")
    }

    private var emptyState: some View {
        VStack(spacing: 10) {
            Image(systemName: "clock.arrow.circlepath")
                .font(.system(size: 44))
                .foregroundStyle(Theme.textTertiary)
                .padding(.top, 60)
            Text("No past flights yet")
                .font(.system(size: 19, weight: .heavy, design: .rounded))
            Text("A flight moves here on its own 30 minutes after it lands.")
                .font(.subheadline)
                .foregroundStyle(Theme.textSecondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding()
    }

    private var noResults: some View {
        Text("Nothing matches “\(query)”.")
            .font(.system(size: 14, weight: .medium, design: .rounded))
            .foregroundStyle(Theme.textSecondary)
            .padding(.top, 40)
    }
}

/// A compact completed-flight row: route, date, duration, and how late it was.
struct PastFlightRow: View {
    let flight: Flight

    private var delayMinutes: Int { flight.arrivalDelayMinutes }

    var body: some View {
        HStack(spacing: 12) {
            AirlineBadge(code: flight.airlineCode, size: 34)

            VStack(alignment: .leading, spacing: 4) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text("\(flight.originIATA) → \(flight.destinationIATA)")
                        .font(Theme.codeFont(19))
                    Text(flight.displayNumber)
                        .font(Theme.monoFont(11))
                        .foregroundStyle(Theme.textTertiary)
                }
                Text(subtitle)
                    .font(.system(size: 11, weight: .medium, design: .rounded))
                    .foregroundStyle(Theme.textSecondary)
                    .lineLimit(1)
            }

            Spacer(minLength: 4)

            VStack(alignment: .trailing, spacing: 4) {
                if flight.phase == .cancelled {
                    StatusPill(text: "Cancelled", color: Theme.red)
                } else if delayMinutes >= Flight.delayThresholdMinutes {
                    StatusPill(text: "+\(delayMinutes)m", color: Theme.orange)
                } else {
                    StatusPill(text: "On Time", color: Theme.green)
                }
                Text(Fmt.duration(flight.duration))
                    .font(.system(size: 11, weight: .bold, design: .rounded))
                    .foregroundStyle(Theme.textTertiary)
            }
        }
        .cardStyle(padding: 12)
    }

    private var subtitle: String {
        var parts = [Fmt.fullDate(flight.bestDeparture, tz: flight.originAirport?.timeZone)]
        if let type = flight.aircraftType { parts.append(type) }
        if let seat = flight.seat { parts.append("Seat \(seat)") }
        else if let tail = flight.tailNumber { parts.append(tail) }
        return parts.joined(separator: " · ")
    }
}
