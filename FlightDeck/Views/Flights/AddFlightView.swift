import SwiftUI

/// Sheet for adding a flight by designator + date.
///
/// Search is the happy path for any date. The live feed reliably answers about
/// a week out; past that the provider asks for the real date anyway and, if
/// it comes back empty, projects this week's timetable for the same flight
/// number onto the chosen day (`ScheduleProjection`), confirmed automatically
/// once the flight is inside the live window. Anything the feed doesn't carry
/// at all falls through to a keyless route lookup and a prefilled manual entry
/// rather than a dead end.
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

    /// How far out the picked date is. Saying what will happen before the
    /// search beats explaining it after.
    private var daysAhead: Int { AeroDataBoxProvider.daysAhead(of: date) }

    private var isBeyondLiveWindow: Bool {
        !isDemo && abs(daysAhead) > AeroDataBoxProvider.liveWindowDays
    }

    var body: some View {
        NavigationStack {
            Form {
                // In Demo Mode a number search can only ever return a made-up
                // flight, so the path that adds a *real* one goes first.
                if isDemo { manualSection }

                Section {
                    TextField("Flight number (e.g. DL 482)", text: $flightNumber)
                        .textInputAutocapitalization(.characters)
                        .autocorrectionDisabled()
                        .scaledFont(17, weight: .semibold, design: .monospaced)
                    DatePicker("Date", selection: $date, displayedComponents: .date)
                } header: {
                    Text("Find a flight")
                } footer: {
                    if isDemo {
                        Text("Demo Mode is on, so any number you search returns a sample flight with made-up times. To add a real flight, use *Add your real flight* above, or add a free AeroDataBox key in Settings.")
                    } else if isBeyondLiveWindow, daysAhead > 0 {
                        Text("That's \(daysAhead) days out. If the live feed doesn't have that date yet, Flight Dash copies this week's timetable for the same flight and confirms it automatically once it's within \(AeroDataBoxProvider.liveWindowDays) days.")
                    } else if isBeyondLiveWindow {
                        Text("That's \(-daysAhead) days ago. How far back lookups reach depends on your AeroDataBox plan — if it isn't found, add it manually below.")
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
                    .disabled(flightNumber.count < 3 || isSearching)

                    if let errorMessage {
                        Text(errorMessage)
                            .font(.footnote)
                            .foregroundStyle(Theme.red)
                    }
                }

                if !results.isEmpty {
                    Section(isDemo ? "Sample results" : "Results") {
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

                if !isDemo { manualSection }

                Section {
                    Button {
                        store.addSampleTrip()
                        dismiss()
                    } label: {
                        Label("Add Sample Trip (4 flights)", systemImage: "wand.and.stars")
                    }
                } footer: {
                    Text("A showcase itinerary built around the current time: one flight in the air now, a JFK → LHR connection, tomorrow's flight, and a completed one. Everything on it is made up.")
                }
            }
            .scrollContentBackground(.hidden)
            .background(Theme.background)
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
        if isDemo || canAddManually || !results.isEmpty || !flightNumber.isEmpty {
            Section {
                Button {
                    showManualEntry = true
                } label: {
                    HStack(spacing: 12) {
                        Image(systemName: "square.and.pencil")
                            .foregroundStyle(Theme.accent)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(manualButtonTitle)
                                .scaledFont(15, weight: .bold)
                                .foregroundStyle(Theme.textPrimary)
                            if let route = lookedUpRoute {
                                Text("\(route.arrow)\(route.airlineName.map { " · \($0)" } ?? "")")
                                    .scaledFont(13, weight: .heavy)
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
                Text(isDemo ? "Add your real flight" : "Enter it yourself")
            } footer: {
                Text(lookedUpRoute == nil
                     ? "Works for any flight, any date, anywhere — including ones the live feed doesn't carry."
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
                    .scaledFont(15, weight: .bold)
                    .monospacedDigit()
                    .foregroundStyle(Theme.textPrimary)
                Text("Departs \(Fmt.time(flight.scheduledDeparture, airportIATA: flight.originIATA)) · \(Fmt.dayAndDate(flight.scheduledDeparture, tz: flight.originAirport?.timeZone))")
                    .font(.footnote)
                    .monospacedDigit()
                    .foregroundStyle(Theme.textSecondary)
                if let reference = flight.projectedFrom {
                    Text("Times copied from \(Fmt.dayAndDate(reference, tz: flight.originAirport?.timeZone)) · confirmed \(AeroDataBoxProvider.liveWindowDays) days out")
                        .scaledFont(11, weight: .semibold)
                        .foregroundStyle(Theme.orange)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer()
            // Demo results are invented from the number typed — say so on the
            // row itself, where the decision to add it is made.
            if isDemo {
                StatusPill(text: "Sample", color: Theme.sample)
            }
            Image(systemName: "plus.circle.fill")
                .foregroundStyle(Theme.accent)
                .accessibilityHidden(true)
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
