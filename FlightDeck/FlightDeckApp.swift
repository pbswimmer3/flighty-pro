import SwiftUI

@main
struct FlightDeckApp: App {
    @StateObject private var settings: SettingsStore
    @StateObject private var flightStore: FlightStore
    @StateObject private var delayHistory: DelayHistoryStore

    init() {
        let settings = SettingsStore()
        let history = DelayHistoryStore()
        _settings = StateObject(wrappedValue: settings)
        _delayHistory = StateObject(wrappedValue: history)
        _flightStore = StateObject(wrappedValue: FlightStore(settings: settings, history: history))
    }

    var body: some Scene {
        WindowGroup {
            RootTabView()
                .environmentObject(settings)
                .environmentObject(flightStore)
                .environmentObject(delayHistory)
                .preferredColorScheme(.dark)
                .tint(Theme.accent)
        }
    }
}
