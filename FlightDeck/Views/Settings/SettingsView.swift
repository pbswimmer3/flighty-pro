import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var settings: SettingsStore
    @EnvironmentObject private var store: FlightStore
    @State private var confirmClear = false

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Toggle("Demo Mode", isOn: $settings.demoMode)
                } header: {
                    Text("Data Source")
                } footer: {
                    Text("Demo Mode generates realistic flights with no setup. Turn it off and add an AeroDataBox key below to track real flights.")
                }

                Section {
                    SecureField("AeroDataBox API key (RapidAPI)", text: $settings.aeroDataBoxKey)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)
                } header: {
                    Text("Live flight lookups")
                } footer: {
                    Text("Free at rapidapi.com — subscribe to AeroDataBox's Basic plan and paste your key. Airport delay status (FAA), weather (METAR), and live aircraft positions (adsb.lol) are keyless and always on.")
                }

                Section("My data") {
                    Button(role: .destructive) {
                        confirmClear = true
                    } label: {
                        Label("Remove All Flights", systemImage: "trash")
                    }
                }

                Section {
                    LabeledContent("Flights tracked", value: "\(store.flights.count)")
                    LabeledContent("Airport database", value: "\(AirportDatabase.shared.airports.count) airports")
                    LabeledContent("Version", value: "1.0")
                } header: {
                    Text("About")
                } footer: {
                    Text("FlightDeck is a personal-use flight tracker inspired by the look and feel of Flighty. Data: FAA NAS Status, NOAA/NWS aviationweather.gov, adsb.lol, and optionally AeroDataBox. Not affiliated with Flighty LLC or any airline.")
                }
            }
            .navigationTitle("Settings")
            .confirmationDialog("Remove all tracked flights?",
                                isPresented: $confirmClear,
                                titleVisibility: .visible) {
                Button("Remove All", role: .destructive) { store.clearAll() }
            }
        }
    }
}
