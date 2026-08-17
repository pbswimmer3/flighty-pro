import SwiftUI

struct RootTabView: View {
    var body: some View {
        TabView {
            MyFlightsView()
                .tabItem { Label("Flights", systemImage: "airplane") }

            PassportView()
                .tabItem { Label("Passport", systemImage: "book.closed.fill") }

            AirportsView()
                .tabItem { Label("Airports", systemImage: "building.2.fill") }

            ConnectionView()
                .tabItem { Label("Connection", systemImage: "arrow.triangle.branch") }

            SettingsView()
                .tabItem { Label("Settings", systemImage: "gearshape.fill") }
        }
        .background(Theme.background)
    }
}

#Preview {
    let settings = SettingsStore()
    let history = DelayHistoryStore()
    RootTabView()
        .environmentObject(settings)
        .environmentObject(history)
        .environmentObject(FlightStore(settings: settings, history: history))
        .preferredColorScheme(.dark)
}
