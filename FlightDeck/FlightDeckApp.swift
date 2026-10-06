import SwiftUI

@main
struct FlightDeckApp: App {
    @StateObject private var settings: SettingsStore
    @StateObject private var flightStore: FlightStore
    @StateObject private var delayHistory: DelayHistoryStore
    @StateObject private var notifications = NotificationService.shared

    init() {
        let settings = SettingsStore()
        let history = DelayHistoryStore()
        _settings = StateObject(wrappedValue: settings)
        _delayHistory = StateObject(wrappedValue: history)
        _flightStore = StateObject(wrappedValue: FlightStore(settings: settings, history: history))
    }

    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            RootTabView()
                .environmentObject(settings)
                .environmentObject(flightStore)
                .environmentObject(delayHistory)
                .environmentObject(notifications)
                .preferredColorScheme(.dark)
                .tint(Theme.accent)
                .task { await syncAlerts() }
                .onChange(of: scenePhase) { _, phase in
                    // Coming back to the app is the moment to re-derive the
                    // schedule: times may have moved while it was away, and
                    // the user may have changed permission in system Settings.
                    guard phase == .active else { return }
                    Task { await syncAlerts() }
                }
        }
    }

    private func syncAlerts() async {
        await notifications.refreshAuthorization()
        flightStore.refreshNotificationSchedule()
    }
}
