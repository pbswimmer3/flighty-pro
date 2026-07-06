import SwiftUI

struct RootTabView: View {
    var body: some View {
        TabView {
            MyFlightsView()
                .tabItem { Label("Flights", systemImage: "airplane") }

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
    RootTabView()
        .environmentObject(SettingsStore())
        .environmentObject(FlightStore(settings: SettingsStore()))
        .preferredColorScheme(.dark)
}
