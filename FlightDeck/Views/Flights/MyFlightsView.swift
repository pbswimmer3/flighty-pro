import SwiftUI

/// Home tab: the user's tracked flights in Flighty-style sections.
struct MyFlightsView: View {
    @EnvironmentObject private var store: FlightStore
    @EnvironmentObject private var settings: SettingsStore
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
                        section("Past", flights: store.pastFlights, icon: "clock.arrow.circlepath")
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
