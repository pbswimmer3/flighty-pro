import SwiftUI

/// Home tab: the user's live flights, in Today / Upcoming sections.
///
/// Only flights that haven't been archived yet appear here — a flight retires
/// itself 30 minutes after landing and moves to the Passport's Past Flights
/// list. See `Flight.archivesAt`.
struct MyFlightsView: View {
    @EnvironmentObject private var store: FlightStore
    @State private var showingAdd = false

    /// A fresh install opens on a sample trip. Without a word of explanation
    /// that reads as somebody else's real flights, so the first launch says
    /// what they are — once.
    @AppStorage("hasSeenWelcome") private var hasSeenWelcome = false
    @State private var showingWelcome = false

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVStack(spacing: 14) {
                    if store.flights.isEmpty {
                        emptyState
                    } else {
                        DemoBanner()

                        section("Today", flights: store.todayFlights, icon: "sun.max.fill")
                        section("Upcoming", flights: store.upcomingFlights, icon: "calendar")

                        if store.todayFlights.isEmpty && store.upcomingFlights.isEmpty {
                            allClearState
                        }

                        // Renders nothing once alerts are decided or the
                        // card was dismissed, so no padding of its own here.
                        AlertsPromptCard()

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
                    .accessibilityLabel("Add Flight")
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
        // Never in screenshot mode: the store captures must open on the
        // flights, not on a sheet covering them.
        .onAppear {
            if !hasSeenWelcome && !ScreenshotMode.isActive {
                showingWelcome = true
            }
        }
        // Marked seen on any dismissal — the button or a swipe down — so it
        // can't come back on the next launch.
        .sheet(isPresented: $showingWelcome, onDismiss: { hasSeenWelcome = true }) {
            WelcomeView()
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
        ContentUnavailableView {
            Label {
                Text("Nothing in the air")
            } icon: {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(Theme.green)
            }
        } description: {
            Text("All \(store.pastFlights.count) of your flights have landed. Add the next one whenever you're ready.")
        } actions: {
            addFlightButton
        }
        .padding(.top, 20)
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
                        .scaledFont(14, weight: .bold)
                        .monospacedDigit()
                        .foregroundStyle(Theme.accent)
                    Spacer()
                    Image(systemName: "chevron.right")
                        .scaledFont(12, weight: .bold, design: .default)
                        .foregroundStyle(Theme.textTertiary)
                        .accessibilityHidden(true)
                }
                .padding(.horizontal, 4)
                .padding(.vertical, 6)
                .frame(minHeight: 44)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
    }

    private var emptyState: some View {
        ContentUnavailableView {
            Label {
                Text("No flights yet")
            } icon: {
                Image(systemName: "airplane.circle.fill")
                    .foregroundStyle(Theme.accent)
            }
        } description: {
            Text("Add a flight by number, or load a sample trip to explore the app.")
        } actions: {
            addFlightButton
            Button("Load Sample Trip") {
                store.addSampleTrip()
            }
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(Theme.accent)
            .frame(minHeight: 44)
        }
        .padding(.top, 60)
    }

    /// Black on the accent blue: white on it is ~3.3:1, black ~5.4:1.
    private var addFlightButton: some View {
        Button {
            showingAdd = true
        } label: {
            Label("Add Flight", systemImage: "plus")
                .font(.headline)
                .padding(.horizontal, 20)
                .frame(minHeight: 44)
                .background(Theme.accent, in: Capsule())
                .foregroundStyle(.black)
        }
        .buttonStyle(.plain)
    }
}
