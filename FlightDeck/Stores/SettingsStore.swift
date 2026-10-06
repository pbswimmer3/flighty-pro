import Foundation
import Combine

/// User settings, persisted to UserDefaults via @Published + didSet
/// (rather than @AppStorage, which doesn't publish changes reliably from
/// inside an ObservableObject).
///
/// Note: the API key would ideally live in the Keychain; UserDefaults keeps
/// the project dependency-free and is acceptable for a personal-use app
/// (documented trade-off in the README).
final class SettingsStore: ObservableObject {
    private let defaults = UserDefaults.standard

    @Published var demoMode: Bool {
        didSet { defaults.set(demoMode, forKey: "demoMode") }
    }

    @Published var aeroDataBoxKey: String {
        didSet { defaults.set(aeroDataBoxKey, forKey: "aeroDataBoxKey") }
    }

    @Published var favoriteAirports: [String] {
        didSet { defaults.set(favoriteAirports, forKey: "favoriteAirports") }
    }

    /// Stored as one encoded blob rather than a key per switch, so a group
    /// added in a later version defaults to on instead of silently off.
    @Published var notifications: NotificationPreferences {
        didSet {
            guard let data = try? JSONEncoder().encode(notifications) else { return }
            defaults.set(data, forKey: "notificationPreferences")
        }
    }

    init() {
        demoMode = defaults.object(forKey: "demoMode") == nil
            ? true
            : defaults.bool(forKey: "demoMode")
        aeroDataBoxKey = defaults.string(forKey: "aeroDataBoxKey") ?? ""
        favoriteAirports = defaults.stringArray(forKey: "favoriteAirports") ?? ["SFO", "JFK", "LHR"]
        notifications = defaults.data(forKey: "notificationPreferences")
            .flatMap { try? JSONDecoder().decode(NotificationPreferences.self, from: $0) }
            ?? NotificationPreferences()
    }

    func toggleFavorite(_ iata: String) {
        if let idx = favoriteAirports.firstIndex(of: iata) {
            favoriteAirports.remove(at: idx)
        } else {
            favoriteAirports.append(iata)
        }
    }

    func isFavorite(_ iata: String) -> Bool { favoriteAirports.contains(iata) }

    /// The active flight data provider given current settings.
    var provider: FlightDataProvider {
        if demoMode || aeroDataBoxKey.isEmpty {
            return DemoFlightProvider()
        }
        return AeroDataBoxProvider(apiKey: aeroDataBoxKey)
    }
}
