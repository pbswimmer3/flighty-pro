import SwiftUI

/// Home tab: the user's live flights in Flighty-style sections.
///
/// Only flights that haven't been archived yet appear here — a flight retires
/// itself 30 minutes after landing and moves to the Passport's Past Flights
/// list. See `Flight.archivesAt`.
struct MyFlightsView: View {
    @EnvironmentObject private var store: FlightStore
    @State private var showingAdd = false

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVStack(spacing: 14) {
                    if store.flights.isEmpty {
                        emptyState
                    } else {
                        section("Today", flights: store.todayFlights, icon: "sun.max.fill")
                        section("Upcoming", flights: store.upcomingFlights, icon: "calendar")

                        if store.todayFlights.isEmpty && store.upcomingFlights.isEmpty {
                            allClearState
                        }
                        pastFlightsLink
                    }
                }
                .padding(.horizontal)
                .padding(.bottom, 24)
            }
            .background(Theme.background)
            .navigationTitle("My Flights")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        showingAdd = true
                    } label: {
                        Image(systemName: "plus.circle.fill")
                            .font(.title3)
                    }
                }
            }
            .sheet(isPresented: $showingAdd) {
                AddFlightView()
            }
            .refreshable {
                await store.refreshActive()
            }
            .navigationDestination(for: Flight.self) { flight in
                FlightDetailView(flightID: flight.id)
            }
        }
    }

    @ViewBuilder
    private func section(_ title: String, flights: [Flight], icon: String) -> some View {
        if !flights.isEmpty {
            SectionHeader(title: title, systemImage: icon)
                .padding(.top, 6)
            ForEach(flights) { flight in
                NavigationLink(value: flight) {
                    FlightCard(flight: flight)
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
        }
    }

    /// Shown once every tracked flight has been archived — better than an
    /// empty screen that looks like the app lost the user's data.
    private var allClearState: some View {
        VStack(spacing: 10) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 40))
                .foregroundStyle(Theme.green)
                .padding(.top, 40)
            Text("Nothing in the air")
                .font(.system(size: 19, weight: .heavy, design: .rounded))
            Text("All \(store.pastFlights.count) of your flights have landed. Add the next one whenever you're ready.")
                .font(.subheadline)
                .foregroundStyle(Theme.textSecondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.bottom, 10)
    }

    /// A peek at the most recent completed flights, with the full log a tap
    /// away in the Passport.
    @ViewBuilder
    private var pastFlightsLink: some View {
        if !store.pastFlights.isEmpty {
            SectionHeader(title: "Recently Flown", systemImage: "clock.arrow.circlepath")
                .padding(.top, 10)

            ForEach(store.pastFlights.prefix(3)) { flight in
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

            NavigationLink {
                PastFlightsView()
            } label: {
                HStack {
                    Text("All \(store.pastFlights.count) past flights")
                        .font(.system(size: 14, weight: .bold, design: .rounded))
                        .foregroundStyle(Theme.accent)
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(Theme.textTertiary)
                }
                .padding(.horizontal, 4)
                .padding(.vertical, 6)
            }
            .buttonStyle(.plain)
        }
    }

    private var emptyState: some View {
        VStack(spacing: 16) {
            Image(systemName: "airplane.circle.fill")
                .font(.system(size: 64))
                .foregroundStyle(Theme.accent)
                .padding(.top, 80)
            Text("No flights yet")
                .font(.system(size: 22, weight: .heavy, design: .rounded))
            Text("Add a flight by number, or load a sample trip to explore the app.")
                .font(.subheadline)
                .foregroundStyle(Theme.textSecondary)
                .multilineTextAlignment(.center)
            Button {
                showingAdd = true
            } label: {
                Label("Add Flight", systemImage: "plus")
                    .font(.headline)
                    .padding(.horizontal, 20)
                    .padding(.vertical, 10)
                    .background(Theme.accent)
                    .foregroundStyle(.white)
                    .clipShape(Capsule())
            }
            Button("Load Sample Trip") {
                store.addSampleTrip()
            }
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(Theme.accent)
        }
        .frame(maxWidth: .infinity)
        .padding()
    }
}
