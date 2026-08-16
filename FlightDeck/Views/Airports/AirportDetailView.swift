import SwiftUI
import MapKit

/// The Airport Intelligence page: live delay status (FAA), decoded weather,
/// facts, and a map — with a plain-English "what's going on" summary.
struct AirportDetailView: View {
    @EnvironmentObject private var settings: SettingsStore
    let airport: Airport

    @State private var events: [AirportEvent] = []
    @State private var metar: Metar?
    @State private var loaded = false

    var body: some View {
        ScrollView {
            VStack(spacing: 14) {
                header
                statusCard
                trafficCard
                weatherCard
                mapCard
                factsCard
            }
            .padding(.horizontal)
            .padding(.bottom, 30)
        }
        .background(Theme.background)
        .navigationTitle(airport.iata)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    settings.toggleFavorite(airport.iata)
                } label: {
                    Image(systemName: settings.isFavorite(airport.iata) ? "star.fill" : "star")
                }
            }
        }
        .task {
            await load()
        }
        .refreshable {
            await load()
        }
    }

    private func load() async {
        if airport.isUS {
            events = await FAAStatusService.shared.events(for: airport.iata)
        }
        metar = await WeatherService.shared.metar(for: airport)
        loaded = true
    }

    // MARK: Header

    private var header: some View {
        VStack(spacing: 6) {
            Text(airport.iata)
                .font(Theme.codeFont(56))
            Text(airport.name)
                .font(.system(size: 16, weight: .bold, design: .rounded))
                .multilineTextAlignment(.center)
            Text("\(airport.city), \(airport.country)")
                .font(.system(size: 13, weight: .medium, design: .rounded))
                .foregroundStyle(Theme.textSecondary)
            HStack(spacing: 6) {
                Image(systemName: "clock.fill").font(.system(size: 11))
                Text("Local time \(airport.localTimeString())")
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
            }
            .foregroundStyle(Theme.accent)
            .padding(.top, 2)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 10)
    }

    // MARK: Live status (Airport Intelligence)

    private var statusCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeader(title: "Live Status", systemImage: "dot.radiowaves.left.and.right")

            if !airport.isUS {
                statusLine(icon: "info.circle.fill", color: Theme.accent,
                           title: "Delay programs unavailable",
                           detail: "Live ground stop/delay data comes from the FAA and covers US airports. Weather intelligence below still applies.")
            } else if !loaded {
                HStack(spacing: 10) {
                    ProgressView()
                    Text("Checking FAA airspace status…")
                        .font(.system(size: 13, weight: .medium, design: .rounded))
                        .foregroundStyle(Theme.textSecondary)
                }
            } else if events.isEmpty {
                statusLine(icon: "checkmark.seal.fill", color: Theme.green,
                           title: "Normal operations",
                           detail: "No FAA ground stops, delay programs, or closures reported for \(airport.iata) right now.")
            } else {
                ForEach(events) { event in
                    statusLine(icon: event.icon, color: event.severityColor,
                               title: event.kind.rawValue, detail: event.summary)
                }
            }
        }
        .cardStyle()
    }

    private func statusLine(icon: String, color: Color, title: String, detail: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 17, weight: .bold))
                .foregroundStyle(color)
                .frame(width: 26)
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.system(size: 15, weight: .heavy, design: .rounded))
                    .foregroundStyle(color)
                Text(detail)
                    .font(.system(size: 13, weight: .medium, design: .rounded))
                    .foregroundStyle(Theme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    // MARK: Weather

    private var weatherCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                SectionHeader(title: "Weather", systemImage: "cloud.sun.fill")
                if let cat = metar?.fltCat {
                    StatusPill(text: cat, color: metar?.flightCategoryColor ?? Theme.textSecondary)
                }
            }
            if let metar {
                if let summary = metar.conditionsSummary {
                    Text(summary)
                        .font(.system(size: 15, weight: .bold, design: .rounded))
                }
                HStack(spacing: 0) {
                    StatBlock(caption: "Temp", value: metar.tempF.map { "\($0)°F" } ?? "—")
                    StatBlock(caption: "Wind", value: metar.wspd.map { "\(Int($0)) kt" } ?? "—")
                    StatBlock(caption: "Visibility", value: metar.visibilityDescription)
                    StatBlock(caption: "Ceiling", value: metar.ceilingDescription)
                }
                Text(metar.windDescription)
                    .font(.system(size: 12, weight: .medium, design: .rounded))
                    .foregroundStyle(Theme.textSecondary)
                if let raw = metar.rawOb {
                    Text(raw)
                        .font(Theme.monoFont(10, weight: .regular))
                        .foregroundStyle(Theme.textTertiary)
                        .padding(.top, 2)
                }
            } else {
                Text(loaded ? "No METAR available for \(airport.icao)." : "Loading METAR…")
                    .font(.system(size: 13, weight: .medium, design: .rounded))
                    .foregroundStyle(Theme.textSecondary)
            }
        }
        .cardStyle()
    }

    // MARK: Live traffic

    private var trafficCard: some View {
        NavigationLink {
            AirportTrafficView(airport: airport)
        } label: {
            HStack(spacing: 12) {
                Image(systemName: "dot.radiowaves.up.forward")
                    .font(.system(size: 17, weight: .bold))
                    .foregroundStyle(Theme.cyan)
                    .frame(width: 26)
                VStack(alignment: .leading, spacing: 3) {
                    Text("Airport-Wide Traffic")
                        .font(.system(size: 15, weight: .heavy, design: .rounded))
                        .foregroundStyle(Theme.textPrimary)
                    // To watch your own aircraft, open the flight itself — this
                    // screen is for the whole field, not one flight.
                    Text("Everything on the taxiways and in the air around \(airport.iata). For your own flight, open it from the Flights tab.")
                        .font(.system(size: 13, weight: .medium, design: .rounded))
                        .foregroundStyle(Theme.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                        .multilineTextAlignment(.leading)
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(Theme.textTertiary)
            }
            .cardStyle()
        }
        .buttonStyle(.plain)
    }

    // MARK: Map & facts

    private var mapCard: some View {
        Map(initialPosition: .region(MKCoordinateRegion(
            center: airport.coordinate,
            span: MKCoordinateSpan(latitudeDelta: 0.06, longitudeDelta: 0.06)))) {
            Annotation(airport.iata, coordinate: airport.coordinate) {
                Image(systemName: "airplane.circle.fill")
                    .font(.title2)
                    .foregroundStyle(Theme.accent)
                    .background(Circle().fill(.white))
            }
        }
        .mapStyle(.imagery)
        .frame(height: 180)
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .allowsHitTesting(false)
    }

    private var factsCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionHeader(title: "Airport Facts", systemImage: "info.circle")
            InfoRow(label: "ICAO", value: airport.icao)
            InfoRow(label: "Time zone", value: airport.tz)
            InfoRow(label: "Min connection (domestic)", value: "\(airport.mctDomestic) min")
            InfoRow(label: "Min connection (international)", value: "\(airport.mctInternational) min")
            if let terminals = airport.terminals {
                Divider().overlay(Theme.separator)
                Text(terminals)
                    .font(.system(size: 13, weight: .medium, design: .rounded))
                    .foregroundStyle(Theme.textSecondary)
            }
        }
        .cardStyle()
    }
}
