import SwiftUI

/// Sheet for adding a flight by designator + date.
struct AddFlightView: View {
    @EnvironmentObject private var store: FlightStore
    @EnvironmentObject private var settings: SettingsStore
    @Environment(\.dismiss) private var dismiss

    @State private var flightNumber = ""
    @State private var date = Date.now
    @State private var isSearching = false
    @State private var results: [Flight] = []
    @State private var errorMessage: String?

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
                    if settings.demoMode || settings.aeroDataBoxKey.isEmpty {
                        Text("Demo Mode is on — lookups return realistic simulated flights. Add an AeroDataBox key in Settings for real data.")
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
        }
        .preferredColorScheme(.dark)
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

    private func search() async {
        isSearching = true
        errorMessage = nil
        results = []
        do {
            results = try await settings.provider.searchFlights(number: flightNumber, date: date)
        } catch {
            errorMessage = error.localizedDescription
        }
        isSearching = false
    }
}
