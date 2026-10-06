import SwiftUI

/// Sheet for adding a flight by designator + date.
///
/// Search is the happy path, but it is not the only path. Live schedule feeds
/// only reach about a week out, so anything booked further ahead — and
/// anything the feed simply doesn't carry — falls through to a keyless route
/// lookup and a prefilled manual entry rather than a dead end.
struct AddFlightView: View {
    @EnvironmentObject private var store: FlightStore
    @EnvironmentObject private var settings: SettingsStore
    @Environment(\.dismiss) private var dismiss

    @State private var flightNumber = ""
    @State private var date = Date.now
    @State private var isSearching = false
    @State private var results: [Flight] = []
    @State private var errorMessage: String?
    @State private var canAddManually = false
    @State private var lookedUpRoute: FlightRouteService.Route?
    @State private var isLookingUpRoute = false
    @State private var showManualEntry = false
    @State private var didAddManually = false

    private var isDemo: Bool { settings.demoMode || settings.aeroDataBoxKey.isEmpty }

    /// How far out the picked date is. Live status feeds don't reach far, and
    /// saying so before the search beats explaining it after.
    private var daysAhead: Int {
        Calendar.current.dateComponents([.day], from: .now, to: date).day ?? 0
    }

    private var isBeyondLiveSchedules: Bool {
        !isDemo && abs(daysAhead) > AeroDataBoxProvider.scheduleHorizonDays
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Flight number (e.g. DL 482)", text: $flightNumber)
                        .textInputAutocapitalization(.characters)
                        .autocorrectionDisabled()
                        .font(Theme.monoFont(17))
                    DatePicker("Date", selection: $date, displayedComponents: .date)
                } header: {
                    Text("Find a flight")
                } footer: {
                    if isDemo {
                        Text("Demo Mode is on — lookups return realistic simulated flights. Add an AeroDataBox key in Settings for real data.")
                    } else if isBeyondLiveSchedules {
                        Text("That's \(abs(daysAhead)) days \(daysAhead < 0 ? "ago" : "out"). Live status only covers about a week either side of today, so add this one manually below — the route and airline still get filled in for you.")
                    }
                }

                Section {
                    Button {
                        Task { await search() }
                    } label: {
                        if isSearching {
                            HStack { ProgressView(); Text("Searching…") }
                        } else {
                            Label("Search", systemImage: "magnifyingglass")
                        }
                    }
                    .disabled(flightNumber.count < 3 || isSearching || isBeyondLiveSchedules)

                    if let errorMessage {
                        Text(errorMessage)
                            .font(.footnote)
                            .foregroundStyle(Theme.red)
                    }
                }

                if !results.isEmpty {
                    Section("Results") {
                        ForEach(results) { flight in
                            Button {
                                store.add(flight)
                                dismiss()
                            } label: {
                                resultRow(flight)
                            }
                        }
                    }
                }

                manualSection

                Section {
                    Button {
                        store.addSampleTrip()
                        dismiss()
                    } label: {
                        Label("Add Sample Trip (4 flights)", systemImage: "wand.and.stars")
                    }
                } footer: {
                    Text("A showcase itinerary: one flight in the air now, a JFK→LHR connection, tomorrow's flight, and a completed one.")
                }
            }
            .navigationTitle("Add Flight")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { dismiss() }
                }
            }
            // Closing this screen from inside the child's dismissal is racy;
            // waiting for `onDismiss` lets the inner sheet finish first.
            .sheet(isPresented: $showManualEntry, onDismiss: {
                if didAddManually { dismiss() }
            }) {
                ManualFlightView(designator: flightNumber,
                                 route: lookedUpRoute,
                                 departureDate: date,
                                 onAdded: { didAddManually = true })
                    .environmentObject(store)
            }
            // The route lookup is keyless and worth doing the moment a
            // plausible designator exists — by the time the search fails, the
            // manual form is already prefilled. `task(id:)` cancels the
            // in-flight one on the next keystroke, so typing "BA137" costs one
            // request rather than three.
            .task(id: flightNumber) {
                lookedUpRoute = nil
                try? await Task.sleep(nanoseconds: 400_000_000)
                guard !Task.isCancelled else { return }
                await lookUpRoute()
            }
        }
        .preferredColorScheme(.dark)
    }

    // MARK: - Manual entry

    @ViewBuilder
    private var manualSection: some View {
        if canAddManually || isBeyondLiveSchedules || !results.isEmpty || !flightNumber.isEmpty {
            Section {
                Button {
                    showManualEntry = true
                } label: {
                    HStack(spacing: 12) {
                        Image(systemName: "square.and.pencil")
                            .foregroundStyle(Theme.accent)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(manualButtonTitle)
                                .font(.system(size: 15, weight: .bold, design: .rounded))
                                .foregroundStyle(Theme.textPrimary)
                            if let route = lookedUpRoute {
                                Text("\(route.arrow)\(route.airlineName.map { " · \($0)" } ?? "")")
                                    .font(.system(size: 13, weight: .heavy, design: .rounded))
                                    .foregroundStyle(Theme.accent)
                            } else if isLookingUpRoute {
                                Text("Looking up the route…")
                                    .font(.footnote)
                                    .foregroundStyle(Theme.textSecondary)
                            }
                        }
                        Spacer()
                    }
                }
            } header: {
                Text("Enter it yourself")
            } footer: {
                Text(lookedUpRoute == nil
                     ? "Works for any flight, any date, anywhere — including flights too far out for live schedules."
                     : "Route and airline come from a free community database keyed on flight number. It's the route this number usually flies, so check it matches your leg — everything is editable.")
            }
        }
    }

    private var manualButtonTitle: String {
        guard let displayNumber = lookedUpRoute?.displayNumber
                ?? DemoFlightProvider.parseDesignator(flightNumber).map({ "\($0.code) \($0.number)" })
        else { return "Add a flight manually" }
        return "Add \(displayNumber) manually"
    }

    private func resultRow(_ flight: Flight) -> some View {
        HStack(spacing: 12) {
            AirlineBadge(code: flight.airlineCode, size: 32)
            VStack(alignment: .leading, spacing: 2) {
                Text("\(flight.displayNumber)  \(flight.originIATA) → \(flight.destinationIATA)")
                    .font(.system(size: 15, weight: .bold, design: .rounded))
                    .foregroundStyle(Theme.textPrimary)
                Text("Departs \(Fmt.time(flight.scheduledDeparture, airportIATA: flight.originIATA)) · \(Fmt.dayAndDate(flight.scheduledDeparture))")
                    .font(.footnote)
                    .foregroundStyle(Theme.textSecondary)
            }
            Spacer()
            Image(systemName: "plus.circle.fill")
                .foregroundStyle(Theme.accent)
        }
    }

    // MARK: - Lookups

    private func search() async {
        isSearching = true
        errorMessage = nil
        canAddManually = false
        results = []
        do {
            results = try await settings.provider.searchFlights(number: flightNumber, date: date)
        } catch {
            errorMessage = error.localizedDescription
            // A missing key or a dead connection is worth fixing, not working
            // around; anything else means the feed genuinely can't answer, and
            // manual entry is the real next step.
            canAddManually = (error as? FlightDataError)?.isWorthAddingManually ?? true
            await lookUpRoute()
        }
        isSearching = false
    }

    private func lookUpRoute() async {
        guard lookedUpRoute == nil,
              DemoFlightProvider.parseDesignator(flightNumber) != nil else { return }
        let query = flightNumber
        isLookingUpRoute = true
        let route = await FlightRouteService.shared.route(for: query)
        // The field may have moved on while the request was out.
        guard query == flightNumber else { isLookingUpRoute = false; return }
        lookedUpRoute = route
        isLookingUpRoute = false
    }
}
