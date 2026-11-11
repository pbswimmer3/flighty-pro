import SwiftUI

struct RootTabView: View {
    @State private var selection = ScreenshotMode.scene?.tab ?? 0

    var body: some View {
        if let scene = ScreenshotMode.scene, scene.tab == nil {
            ScreenshotRoot(scene: scene)
        } else {
            tabs
        }
    }

    private var tabs: some View {
        TabView(selection: $selection) {
            MyFlightsView()
                .tabItem { Label("Flights", systemImage: "airplane") }
                .tag(0)

            PassportView()
                .tabItem { Label("Passport", systemImage: "book.closed.fill") }
                .tag(1)

            AirportsView()
                .tabItem { Label("Airports", systemImage: "building.2.fill") }
                .tag(2)

            ConnectionView()
                .tabItem { Label("Connection", systemImage: "arrow.triangle.branch") }
                .tag(3)

            SettingsView()
                .tabItem { Label("Settings", systemImage: "gearshape.fill") }
                .tag(4)
        }
        .background(Theme.background)
        .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
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
