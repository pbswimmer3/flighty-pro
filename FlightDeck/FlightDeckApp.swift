import SwiftUI

@main
struct FlightDeckApp: App {
    @StateObject private var settings = SettingsStore()
    @StateObject private var flightStore: FlightStore

    init() {
        let settings = SettingsStore()
        _settings = StateObject(wrappedValue: settings)
        _flightStore = StateObject(wrappedValue: FlightStore(settings: settings))
    }

    var body: some Scene {
        WindowGroup {
            RootTabView()
                .environmentObject(settings)
                .environmentObject(flightStore)
                .preferredColorScheme(.dark)
                .tint(Theme.accent)
        }
    }
}
