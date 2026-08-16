import SwiftUI

/// The Passport: a lifetime (or per-year) record of everywhere you've flown.
///
/// Everything here is derived from the flight log on the fly — see
/// `PassportStats.build`. Nothing is stored twice, so a flight you delete
/// disappears from the stats immediately.
struct PassportView: View {
    @EnvironmentObject private var store: FlightStore
    @State private var scope: PassportStats.Scope = .allTime

    var body: some View {
        // Built once per render rather than per card: `availableYears` is
        // filled in regardless of scope, so the picker comes free with it.
        let stats = store.passport(scope: scope)
        let scopes: [PassportStats.Scope] =
            [.allTime] + stats.availableYears.map { PassportStats.Scope.year($0) }

        return NavigationStack {
            ScrollView {
                LazyVStack(spacing: 14) {
                    if scopes.count > 1 {
                        ScopePicker(scopes: scopes, selection: $scope)
                            .padding(.top, 2)
                    }

                    if stats.isEmpty {
                        emptyState
                    } else {
                        heroCard(stats)
                        PassportMapCard(stats: stats)
                        delayCard(stats)
                        aircraftCard(stats)
                        RankedCard(title: "Airlines",
                                   systemImage: "building.2.crop.circle",
                                   rows: stats.airlines,
                                   tint: Theme.purple)
                        RankedCard(title: "Airports",
                                   systemImage: "mappin.and.ellipse",
                                   rows: stats.airports,
                                   unit: "visits",
                                   tint: Theme.cyan)
                        routesCard(stats)
                        shapeCard(stats)
                        superlativesCard(stats)
                        pastFlightsLink(stats)
                    }
                }
                .padding(.horizontal)
                .padding(.bottom, 30)
            }
            .background(Theme.background)
            .navigationTitle("Passport")
            .navigationDestination(for: Flight.self) { flight in
                FlightDetailView(flightID: flight.id)
            }
        }
    }

    // MARK: - Hero

    private func heroCard(_ stats: PassportStats) -> some View {
        VStack(spacing: 12) {
            HStack(spacing: 10) {
                PassportTile(value: "\(stats.flightCount)",
                             caption: stats.flightCount == 1 ? "Flight" : "Flights",
                             footnote: scope == .allTime ? "All time" : scope.label,
                             systemImage: "airplane",
                             color: Theme.accent)
                PassportTile(value: Fmt.grouped(stats.totalMiles),
                             caption: "Miles flown",
                             footnote: aroundTheWorldFootnote(stats),
                             systemImage: "globe",
                             color: Theme.cyan)
            }
            HStack(spacing: 10) {
                PassportTile(value: Fmt.longDuration(stats.totalAirTime),
                             caption: "Time in the air",
                             footnote: "Average \(Fmt.duration(stats.averageFlightLength)) per flight",
                             systemImage: "clock.fill",
                             color: Theme.purple)
                PassportTile(value: "\(stats.airports.count)",
                             caption: "Airports",
                             footnote: "\(stats.countries.count) \(stats.countries.count == 1 ? "country" : "countries") · \(stats.airlines.count) \(stats.airlines.count == 1 ? "airline" : "airlines")",
                             systemImage: "mappin.and.ellipse",
                             color: Theme.green)
            }
        }
    }

    private func aroundTheWorldFootnote(_ stats: PassportStats) -> String {
        let laps = stats.timesAroundTheWorld
        if laps >= 1 {
            return String(format: "%.1f× around the world", laps)
        }
        if laps <= 0 { return "Add a flight to start counting" }
        return String(format: "%.0f%% of the way around the world", laps * 100)
    }

    // MARK: - Delay tracker

    private func delayCard(_ stats: PassportStats) -> some View {
        let delays = stats.delays
        return NavigationLink {
            DelayTrackerView(stats: stats)
        } label: {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    SectionHeader(title: "Delay Tracker", systemImage: "clock.badge.exclamationmark")
                    Image(systemName: "chevron.right")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(Theme.textTertiary)
                }

                HStack(spacing: 0) {
                    StatBlock(caption: "Delayed",
                              value: "\(delays.delayedFlights)",
                              color: delays.delayedFlights > 0 ? Theme.orange : Theme.green)
                    StatBlock(caption: "On time",
                              value: Fmt.percent(delays.onTimeRate),
                              color: Theme.green)
                    StatBlock(caption: "Time lost",
                              value: Fmt.longDuration(delays.totalDelayInterval),
                              color: Theme.orange)
                    StatBlock(caption: "Cancelled",
                              value: "\(delays.cancelledFlights)",
                              color: delays.cancelledFlights > 0 ? Theme.red : Theme.textPrimary)
                }

                if let worst = delays.worst {
                    Divider().overlay(Theme.separator)
                    HStack(spacing: 10) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundStyle(Theme.red)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Worst delay: \(Fmt.duration(TimeInterval(worst.minutes) * 60))")
                                .font(.system(size: 14, weight: .heavy, design: .rounded))
                                .foregroundStyle(Theme.textPrimary)
                            Text("\(worst.designator) · \(worst.route) · \(Fmt.fullDate(worst.date))")
                                .font(.system(size: 12, weight: .medium, design: .rounded))
                                .foregroundStyle(Theme.textSecondary)
                        }
                        Spacer()
                    }
                } else if delays.flightsCounted > 0 {
                    Text("Not one delayed arrival on record. Enjoy it while it lasts.")
                        .font(.system(size: 13, weight: .medium, design: .rounded))
                        .foregroundStyle(Theme.green)
                }

                Text("Counted the way the US DOT does: an arrival \(Flight.delayThresholdMinutes)+ minutes behind schedule.")
                    .font(.system(size: 11, weight: .medium, design: .rounded))
                    .foregroundStyle(Theme.textTertiary)
            }
            .cardStyle()
        }
        .buttonStyle(.plain)
    }

    // MARK: - Aircraft

    private func aircraftCard(_ stats: PassportStats) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionHeader(title: "Most Flown Aircraft", systemImage: "airplane.circle.fill")

            if let top = stats.mostFlownAircraft {
                HStack(spacing: 14) {
                    ZStack {
                        Circle().fill(Theme.accent.opacity(0.18))
                        Image(systemName: "airplane")
                            .font(.system(size: 22, weight: .bold))
                            .foregroundStyle(Theme.accent)
                            .rotationEffect(.degrees(-45))
                    }
                    .frame(width: 56, height: 56)

                    VStack(alignment: .leading, spacing: 3) {
                        Text(top.label)
                            .font(.system(size: 18, weight: .heavy, design: .rounded))
                            .foregroundStyle(Theme.textPrimary)
                            .lineLimit(2)
                        Text("\(top.count) \(top.count == 1 ? "flight" : "flights") · \(Fmt.percent(Double(top.count) / Double(max(stats.flightCount, 1)))) of everything you've flown")
                            .font(.system(size: 12, weight: .medium, design: .rounded))
                            .foregroundStyle(Theme.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer(minLength: 0)
                }

                if stats.aircraft.count > 1 {
                    Divider().overlay(Theme.separator).padding(.vertical, 2)
                    let peak = stats.aircraft.first?.count ?? 1
                    ForEach(Array(stats.aircraft.dropFirst().prefix(4).enumerated()),
                            id: \.element.id) { index, tally in
                        RankRow(rank: index + 2,
                                title: tally.label,
                                subtitle: nil,
                                count: tally.count,
                                maxCount: peak)
                    }
                }

                if let airframe = stats.airframes.first, airframe.count > 1 {
                    Divider().overlay(Theme.separator).padding(.vertical, 2)
                    InfoRow(label: "Most-flown airframe",
                            value: "\(airframe.label) · \(airframe.count)×")
                    if let type = airframe.detail {
                        Text(type)
                            .font(.system(size: 11, weight: .medium, design: .rounded))
                            .foregroundStyle(Theme.textTertiary)
                    }
                }
            } else {
                Text("No aircraft types recorded yet. They arrive automatically with live flight lookups.")
                    .font(.system(size: 13, weight: .medium, design: .rounded))
                    .foregroundStyle(Theme.textSecondary)
            }
        }
        .cardStyle()
    }

    // MARK: - Routes

    private func routesCard(_ stats: PassportStats) -> some View {
        let rows = stats.routes.prefix(6).map { route in
            PassportStats.Tally(key: route.id,
                                label: route.label,
                                detail: route.miles > 0 ? "\(Fmt.grouped(route.miles)) mi total" : nil,
                                count: route.count)
        }
        return RankedCard(title: "Most Flown Routes",
                          systemImage: "arrow.left.arrow.right",
                          rows: Array(rows),
                          collapsedCount: 6,
                          emptyMessage: "No completed routes yet.")
    }

    // MARK: - Shape of your flying

    private func shapeCard(_ stats: PassportStats) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeader(title: "How You Fly", systemImage: "chart.bar.xaxis")

            HStack(spacing: 0) {
                StatBlock(caption: "Domestic", value: "\(stats.domesticCount)")
                StatBlock(caption: "International", value: "\(stats.internationalCount)", color: Theme.cyan)
                StatBlock(caption: "Long haul", value: "\(stats.longHaulCount)", color: Theme.purple)
                StatBlock(caption: "Red-eyes", value: "\(stats.redEyeCount)", color: Theme.orange)
            }

            Divider().overlay(Theme.separator)

            Text("Departures by day of week")
                .font(.system(size: 12, weight: .bold, design: .rounded))
                .foregroundStyle(Theme.textSecondary)
            WeekdayChart(histogram: stats.weekdayHistogram)
        }
        .cardStyle()
    }

    // MARK: - Superlatives

    private func superlativesCard(_ stats: PassportStats) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionHeader(title: "Records", systemImage: "trophy.fill")

            if let longest = stats.longestFlight {
                InfoRow(label: "Longest flight",
                        value: "\(longest.originIATA)→\(longest.destinationIATA) · \(Fmt.duration(longest.duration))")
            }
            if let shortest = stats.shortestFlight, shortest.id != stats.longestFlight?.id {
                InfoRow(label: "Shortest flight",
                        value: "\(shortest.originIATA)→\(shortest.destinationIATA) · \(Fmt.duration(shortest.duration))")
            }
            if let route = stats.mostFlownRoute {
                InfoRow(label: "Most flown route", value: "\(route.label) · \(route.count)×")
            }
            if let airline = stats.mostFlownAirline {
                InfoRow(label: "Most flown airline", value: "\(airline.label) · \(airline.count)×")
            }
            if let seat = stats.seats.first {
                InfoRow(label: "Top seat", value: "\(seat.label) · \(seat.count)×")
            } else {
                Text("Add a seat on any flight page and your top seat shows up here.")
                    .font(.system(size: 11, weight: .medium, design: .rounded))
                    .foregroundStyle(Theme.textTertiary)
            }
            if stats.totalMiles > 0 {
                InfoRow(label: "Toward the moon",
                        value: Fmt.percent(stats.fractionOfWayToTheMoon),
                        valueColor: Theme.textSecondary)
            }
        }
        .cardStyle()
    }

    // MARK: - Past flights

    private func pastFlightsLink(_ stats: PassportStats) -> some View {
        NavigationLink {
            PastFlightsView()
        } label: {
            HStack(spacing: 12) {
                Image(systemName: "clock.arrow.circlepath")
                    .font(.system(size: 17, weight: .bold))
                    .foregroundStyle(Theme.accent)
                    .frame(width: 26)
                VStack(alignment: .leading, spacing: 3) {
                    Text("Past Flights")
                        .font(.system(size: 15, weight: .heavy, design: .rounded))
                        .foregroundStyle(Theme.textPrimary)
                    Text("\(stats.flightCount) flown. Flights move here automatically 30 minutes after landing.")
                        .font(.system(size: 13, weight: .medium, design: .rounded))
                        .foregroundStyle(Theme.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                        .multilineTextAlignment(.leading)
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(Theme.textTertiary)
            }
            .cardStyle()
        }
        .buttonStyle(.plain)
    }

    // MARK: - Empty

    private var emptyState: some View {
        VStack(spacing: 14) {
            Image(systemName: "book.closed.fill")
                .font(.system(size: 56))
                .foregroundStyle(Theme.accent)
                .padding(.top, 70)
            Text("Your Passport is empty")
                .font(.system(size: 22, weight: .heavy, design: .rounded))
            Text("Every flight you take gets folded in here automatically once it lands — distance, hours in the air, airports, airlines, aircraft and every minute you've lost to delays.")
                .font(.subheadline)
                .foregroundStyle(Theme.textSecondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 8)
            if scope != .allTime {
                Button("Show all time") { scope = .allTime }
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Theme.accent)
            }
        }
        .frame(maxWidth: .infinity)
        .padding()
    }
}
