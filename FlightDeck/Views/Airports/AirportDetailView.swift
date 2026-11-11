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
                .accessibilityLabel(settings.isFavorite(airport.iata) ? "Remove from Favorites" : "Add to Favorites")
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
                .scaledFont(56, weight: .heavy)
            Text(airport.name)
                .scaledFont(16, weight: .bold)
                .multilineTextAlignment(.center)
            Text("\(airport.city), \(airport.country)")
                .scaledFont(13, weight: .medium)
                .foregroundStyle(Theme.textSecondary)
            HStack(spacing: 6) {
                Image(systemName: "clock.fill").scaledFont(11, design: .default)
                Text("Local time \(airport.localTimeString())")
                    .scaledFont(13, weight: .semibold)
                    .monospacedDigit()
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
                        .scaledFont(13, weight: .medium)
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
                .scaledFont(17, weight: .bold, design: .default)
                .foregroundStyle(color)
                .frame(width: 26)
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .scaledFont(15, weight: .heavy)
                    .foregroundStyle(color)
                Text(detail)
                    .scaledFont(13, weight: .medium)
                    .foregroundStyle(Theme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .accessibilityElement(children: .combine)
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
                        .scaledFont(15, weight: .bold)
                }
                HStack(spacing: 0) {
                    StatBlock(caption: "Temp", value: metar.tempF.map { "\($0)°F" } ?? "—")
                    StatBlock(caption: "Wind", value: metar.wspd.map { "\(Int($0)) kt" } ?? "—")
                    StatBlock(caption: "Visibility", value: metar.visibilityDescription)
                    StatBlock(caption: "Ceiling", value: metar.ceilingDescription)
                }
                Text(metar.windDescription)
                    .scaledFont(12, weight: .medium)
                    .foregroundStyle(Theme.textSecondary)
                if let raw = metar.rawOb {
                    Text(raw)
                        .scaledFont(11, weight: .regular, design: .monospaced)
                        .foregroundStyle(Theme.textTertiary)
                        .padding(.top, 2)
                }
            } else {
                Text(loaded ? "No METAR available for \(airport.icao)." : "Loading METAR…")
                    .scaledFont(13, weight: .medium)
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
                    .scaledFont(17, weight: .bold, design: .default)
                    .foregroundStyle(Theme.cyan)
                    .frame(width: 26)
                VStack(alignment: .leading, spacing: 3) {
                    Text("Airport-Wide Traffic")
                        .scaledFont(15, weight: .heavy)
                        .foregroundStyle(Theme.textPrimary)
                    // To watch your own aircraft, open the flight itself — this
                    // screen is for the whole field, not one flight.
                    Text("Everything on the taxiways and in the air around \(airport.iata). For your own flight, open it from the Flights tab.")
                        .scaledFont(13, weight: .medium)
                        .foregroundStyle(Theme.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                        .multilineTextAlignment(.leading)
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .scaledFont(13, weight: .bold, design: .default)
                    .foregroundStyle(Theme.textTertiary)
                    .accessibilityHidden(true)
            }
            .cardStyle()
            .accessibilityElement(children: .combine)
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
        .clipShape(RoundedRectangle(cornerRadius: Theme.radiusCard, style: .continuous))
        .allowsHitTesting(false)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Satellite map of \(airport.iata)")
    }

    private var factsCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionHeader(title: "Airport Facts", systemImage: "info.circle")
            InfoRow(label: "ICAO", value: airport.icao)
            InfoRow(label: "Time zone",
                    value: airport.timeZone.localizedName(for: .generic, locale: .current) ?? airport.tz)
            InfoRow(label: "Min connection (domestic)", value: mctText(airport.mctDomestic))
            InfoRow(label: "Min connection (international)", value: mctText(airport.mctInternational))
            if !airport.hasResearchedConnectionTimes {
                Text("Connection times here are typical defaults, not researched values for this airport.")
                    .scaledFont(12, weight: .medium)
                    .foregroundStyle(Theme.textTertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if let terminals = airport.terminals {
                Divider().overlay(Theme.separator)
                Text(terminals)
                    .scaledFont(13, weight: .medium)
                    .foregroundStyle(Theme.textSecondary)
            }
        }
        .cardStyle()
    }

    private func mctText(_ minutes: Int) -> String {
        airport.hasResearchedConnectionTimes ? "\(minutes) min" : "~\(minutes) min"
    }
}
