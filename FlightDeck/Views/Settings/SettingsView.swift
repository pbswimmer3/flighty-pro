import SwiftUI
import UIKit   // openSettingsURLString, for the notifications-denied case

struct SettingsView: View {
    @EnvironmentObject private var settings: SettingsStore
    @EnvironmentObject private var store: FlightStore
    @EnvironmentObject private var history: DelayHistoryStore
    @EnvironmentObject private var notifications: NotificationService
    @State private var confirmClear = false
    @State private var confirmClearHistory = false
    @State private var didSendTest = false

    var body: some View {
        NavigationStack {
            Form {
                notificationSection

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

                Section {
                    LabeledContent("Observations stored",
                                   value: "\(history.observations.count)")
                    LabeledContent("Analysis window",
                                   value: "\(DelayObservation.analysisWindowDays) days")
                    Button(role: .destructive) {
                        confirmClearHistory = true
                    } label: {
                        Label("Clear Punctuality History", systemImage: "chart.bar.xaxis")
                    }
                } header: {
                    Text("Arrival forecast")
                } footer: {
                    Text("Flights you've taken are folded into this record automatically. In Demo Mode the forecast also uses generated history, clearly labelled wherever it appears. Clearing it doesn't touch your flights or your Passport.")
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
                    LabeledContent("Flights flown", value: "\(store.passport().flightCount)")
                    LabeledContent("Airport database", value: "\(AirportDatabase.shared.airports.count) airports")
                    LabeledContent("Version", value: "1.1")
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
            } message: {
                Text("This clears your Passport too — every stat here is computed from your flights.")
            }
            .confirmationDialog("Clear punctuality history?",
                                isPresented: $confirmClearHistory,
                                titleVisibility: .visible) {
                Button("Clear History", role: .destructive) { history.clearAll() }
            } message: {
                Text("Arrival forecasts fall back to the industry baseline until history rebuilds.")
            }
            .task { await notifications.refreshAuthorization() }
        }
    }

    // MARK: - Notifications

    @ViewBuilder
    private var notificationSection: some View {
        Section {
            switch notifications.authorization {
            case .notDetermined:
                Button {
                    Task {
                        await notifications.requestAuthorization()
                        store.refreshNotificationSchedule()
                    }
                } label: {
                    Label("Turn On Flight Alerts", systemImage: "bell.badge.fill")
                }

            case .denied:
                Label("Notifications are off in iOS Settings", systemImage: "bell.slash.fill")
                    .foregroundStyle(Theme.orange)
                if let url = URL(string: UIApplication.openSettingsURLString) {
                    Link(destination: url) {
                        Label("Open iOS Settings", systemImage: "arrow.up.forward.app")
                    }
                }

            default:
                Toggle("Flight Alerts", isOn: Binding(
                    get: { settings.notifications.isEnabled },
                    set: { newValue in
                        settings.notifications.isEnabled = newValue
                        store.refreshNotificationSchedule()
                    }))

                if settings.notifications.isEnabled {
                    ForEach(FlightAlert.Group.allCases) { group in
                        Toggle(isOn: Binding(
                            get: { settings.notifications.allows(group: group) },
                            set: { newValue in
                                settings.notifications.set(group, enabled: newValue)
                                store.refreshNotificationSchedule()
                            })) {
                                VStack(alignment: .leading, spacing: 2) {
                                    Label(group.title, systemImage: group.systemImage)
                                    Text(group.detail)
                                        .font(.caption)
                                        .foregroundStyle(Theme.textSecondary)
                                }
                            }
                    }

                    LabeledContent("Alerts queued with iOS",
                                   value: "\(notifications.scheduledCount)")

                    Button {
                        Task {
                            await notifications.sendTestAlert()
                            didSendTest = true
                        }
                    } label: {
                        Label(didSendTest ? "Test alert sent — arrives in 5s" : "Send a Test Alert",
                              systemImage: "paperplane.fill")
                    }
                    .disabled(didSendTest)
                }
            }
        } header: {
            Text("Alerts")
        } footer: {
            Text(notificationFooter)
        }
    }

    /// Deliberately explicit about the limitation. Boarding, gate-close,
    /// departure and landing alerts are handed to iOS in advance, so they fire
    /// with the app closed. Gate changes and new delays are only discovered
    /// when the app refreshes — there's no push server behind this — and
    /// pretending otherwise would be the worst kind of bug to find out about
    /// at an airport.
    private var notificationFooter: String {
        switch notifications.authorization {
        case .denied:
            return "iOS is blocking alerts for FlightDeck. Turn them back on in iOS Settings to get boarding and gate alerts."
        case .notDetermined:
            return "Boarding, gate-close, departure, landing and baggage alerts are scheduled on your device, so they arrive even when FlightDeck isn't open."
        default:
            return "Timed alerts (boarding, gate close, departure, landing, bags) are scheduled ahead on your device and arrive with the app closed. Change alerts — a new delay, a gate move, a cancellation — are found when the app refreshes, so open FlightDeck to pick them up. There's no push server behind this app."
        }
    }
}
