import Foundation
import SwiftUI

/// User settings, persisted to UserDefaults.
/// Note: the API key would ideally live in the Keychain; UserDefaults keeps
/// the project dependency-free and is acceptable for a personal-use app
/// (documented trade-off in the README).
final class SettingsStore: ObservableObject {
    @AppStorage("demoMode") var demoMode: Bool = true
    @AppStorage("aeroDataBoxKey") var aeroDataBoxKey: String = ""
    @AppStorage("favoriteAirports") private var favoriteAirportsRaw: String = "SFO,JFK,LHR"

    var favoriteAirports: [String] {
        get { favoriteAirportsRaw.split(separator: ",").map(String.init).filter { !$0.isEmpty } }
        set {
            favoriteAirportsRaw = newValue.joined(separator: ",")
            objectWillChange.send()
        }
    }

    func toggleFavorite(_ iata: String) {
        var favs = favoriteAirports
        if let idx = favs.firstIndex(of: iata) {
            favs.remove(at: idx)
        } else {
            favs.append(iata)
        }
        favoriteAirports = favs
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
