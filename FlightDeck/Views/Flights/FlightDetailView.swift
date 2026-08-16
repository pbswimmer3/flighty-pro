import SwiftUI

/// Full flight page: map header, status banner, delay-intel signals,
/// event timeline, departure/arrival cards, aircraft, inbound plane, weather.
struct FlightDetailView: View {
    @EnvironmentObject private var store: FlightStore
    let flightID: UUID

    @State private var signals: [IntelSignal] = []
    @State private var originMetar: Metar?
    @State private var destinationMetar: Metar?
    /// Owned here so both the map and the traffic link see the same live track.
    @StateObject private var tracker = AircraftTracker()

    private var flight: Flight? {
        store.flights.first { $0.id == flightID }
    }

    var body: some View {
        Group {
            if let flight {
                content(flight)
            } else {
                Text("Flight removed")
                    .foregroundStyle(Theme.textSecondary)
            }
        }
        .background(Theme.background)
    }

    private func content(_ flight: Flight) -> some View {
        ScrollView {
            VStack(spacing: 14) {
                FlightMapView(flight: flight, tracker: tracker)
                    .frame(height: 260)
                    .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))

                statusBanner(flight)
                nearbyTrafficLink(flight)
                intelCard
                timelineCard(flight)
                endpointCard(flight, isDeparture: true)
                endpointCard(flight, isDeparture: false)
                inboundCard(flight)
                aircraftCard(flight)
                weatherCards(flight)
            }
            .padding(.horizontal)
            .padding(.bottom, 30)
        }
        .navigationTitle("\(flight.displayNumber)")
        .navigationBarTitleDisplayMode(.inline)
        .refreshable {
            await store.refresh(flight)
            await loadIntel(flight)
        }
        .task(id: flight.lastUpdated) {
            await loadIntel(flight)
        }
    }

    // MARK: Status banner

    private func statusBanner(_ flight: Flight) -> some View {
        let phase = flight.effectivePhase
        return HStack(spacing: 12) {
            Image(systemName: phase.isAirborne ? "airplane" : phase.isComplete ? "checkmark.circle.fill" : "clock.fill")
                .font(.title3)
            VStack(alignment: .leading, spacing: 2) {
                Text(bannerTitle(flight))
                    .font(.system(size: 17, weight: .heavy, design: .rounded))
                Text(bannerSubtitle(flight))
                    .font(.system(size: 13, weight: .medium, design: .rounded))
                    .opacity(0.8)
            }
            Spacer()
        }
        .foregroundStyle(.white)
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(bannerColor(flight).opacity(0.85))
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
    }

    private func bannerTitle(_ flight: Flight) -> String {
        switch flight.effectivePhase {
        case .cancelled: return "Flight cancelled"
        case .diverted: return "Flight diverted"
        case .enRoute: return "En route to \(flight.destinationIATA)"
        case .landed, .arrived: return "Arrived at \(flight.destinationIATA)"
        case .boarding: return "Boarding soon"
        case .scheduled:
            return flight.isDelayed
                ? "Delayed — departs \(Fmt.delta(flight.departureDelayMinutes))"
                : "On time"
        }
    }

    private func bannerSubtitle(_ flight: Flight) -> String {
        switch flight.effectivePhase {
        case .enRoute:
            return "Lands \(Fmt.relative(flight.bestArrival)) · \(Fmt.time(flight.bestArrival, airportIATA: flight.destinationIATA)) local"
        case .landed, .arrived:
            return "Landed \(Fmt.time(flight.bestArrival, airportIATA: flight.destinationIATA)) local"
        case .cancelled, .diverted:
            return "Check with \(flight.airlineName) for rebooking"
        default:
            return "Departs \(Fmt.relative(flight.bestDeparture)) · \(Fmt.time(flight.bestDeparture, airportIATA: flight.originIATA)) local"
        }
    }

    private func bannerColor(_ flight: Flight) -> Color {
        switch flight.effectivePhase {
        case .cancelled, .diverted: return Theme.red
        case .landed, .arrived: return Theme.green
        default: return flight.isDelayed ? Theme.orange : Theme.accent
        }
    }

    // MARK: Nearby traffic

    /// Only offered once we actually have the airframe on ADS-B — otherwise
    /// there's no "your aircraft" to centre on.
    @ViewBuilder
    private func nearbyTrafficLink(_ flight: Flight) -> some View {
        if let track = tracker.track {
            NavigationLink {
                NearbyTrafficView(flight: flight, tracker: tracker)
            } label: {
                HStack(spacing: 12) {
                    Image(systemName: "dot.radiowaves.up.forward")
                        .font(.system(size: 17, weight: .bold))
                        .foregroundStyle(Theme.cyan)
                        .frame(width: 26)
                    VStack(alignment: .leading, spacing: 3) {
                        Text("Traffic near your aircraft")
                            .font(.system(size: 15, weight: .heavy, design: .rounded))
                            .foregroundStyle(Theme.textPrimary)
                        Text(trackSummary(track))
                            .font(.system(size: 13, weight: .medium, design: .rounded))
                            .foregroundStyle(Theme.textSecondary)
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
    }

    private func trackSummary(_ track: TrafficStore.Track) -> String {
        var parts: [String] = []
        if let altitude = track.report.altitudeFeet {
            parts.append("\(altitude) ft")
        } else if track.report.onGround {
            parts.append("On the ground")
        }
        if let speed = track.report.groundSpeedKts {
            parts.append("\(Int(speed)) kt")
        }
        if let accuracy = track.report.accuracyMetres {
            parts.append("±\(Int(accuracy)) m")
        }
        return parts.isEmpty ? "Live ADS-B contact" : parts.joined(separator: " · ")
    }

    // MARK: Intel signals

    @ViewBuilder
    private var intelCard: some View {
        if !signals.isEmpty {
            VStack(alignment: .leading, spacing: 12) {
                SectionHeader(title: "Flight Intel", systemImage: "brain.head.profile")
                ForEach(signals) { signal in
                    HStack(alignment: .top, spacing: 10) {
                        Image(systemName: signal.icon)
                            .font(.system(size: 15, weight: .bold))
                            .foregroundStyle(signal.color)
                            .frame(width: 24)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(signal.title)
                                .font(.system(size: 14, weight: .bold, design: .rounded))
                            Text(signal.detail)
                                .font(.system(size: 12, weight: .medium, design: .rounded))
                                .foregroundStyle(Theme.textSecondary)
                        }
                    }
                }
            }
            .cardStyle()
        }
    }

    // MARK: Timeline

    private func timelineCard(_ flight: Flight) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            SectionHeader(title: "Timeline", systemImage: "list.bullet.rectangle")
                .padding(.bottom, 10)
            ForEach(timelineEntries(flight), id: \.title) { entry in
                timelineRow(entry)
            }
        }
        .cardStyle()
    }

    private struct TimelineEntry {
        var title: String
        var time: String
        var done: Bool
        var highlight: Bool
    }

    private func timelineEntries(_ flight: Flight) -> [TimelineEntry] {
        let now = Date.now
        let boardingTime = flight.bestDeparture.addingTimeInterval(-40 * 60)
        let dep = flight.bestDeparture
        let arr = flight.bestArrival
        let phase = flight.effectivePhase
        return [
            TimelineEntry(title: "Boarding\(flight.departureGate.map { " · Gate \($0)" } ?? "")",
                          time: Fmt.time(boardingTime, airportIATA: flight.originIATA),
                          done: now >= boardingTime || phase.isAirborne || phase.isComplete,
                          highlight: phase == .boarding),
            TimelineEntry(title: "Departure \(flight.originIATA)",
                          time: Fmt.time(dep, airportIATA: flight.originIATA),
                          done: now >= dep || phase.isAirborne || phase.isComplete,
                          highlight: phase.isAirborne),
            TimelineEntry(title: "Arrival \(flight.destinationIATA)\(flight.arrivalGate.map { " · Gate \($0)" } ?? "")",
                          time: Fmt.time(arr, airportIATA: flight.destinationIATA),
                          done: phase.isComplete,
                          highlight: false),
            TimelineEntry(title: "Baggage\(flight.baggageClaim.map { " · Claim \($0)" } ?? "")",
                          time: Fmt.time(arr.addingTimeInterval(25 * 60), airportIATA: flight.destinationIATA),
                          done: now >= arr.addingTimeInterval(25 * 60) && phase.isComplete,
                          highlight: false),
        ]
    }

    private func timelineRow(_ entry: TimelineEntry) -> some View {
        HStack(spacing: 12) {
            Image(systemName: entry.done ? "checkmark.circle.fill" : "circle")
                .foregroundStyle(entry.done ? Theme.green : entry.highlight ? Theme.accent : Theme.textTertiary)
            Text(entry.title)
                .font(.system(size: 14, weight: entry.highlight ? .heavy : .semibold, design: .rounded))
                .foregroundStyle(entry.done || entry.highlight ? Theme.textPrimary : Theme.textSecondary)
            Spacer()
            Text(entry.time)
                .font(Theme.monoFont(13))
                .foregroundStyle(Theme.textSecondary)
        }
        .padding(.vertical, 7)
    }

    // MARK: Departure / arrival cards

    private func endpointCard(_ flight: Flight, isDeparture: Bool) -> some View {
        let iata = isDeparture ? flight.originIATA : flight.destinationIATA
        let airport = AirportDatabase.shared.airport(iata: iata)
        let scheduled = isDeparture ? flight.scheduledDeparture : flight.scheduledArrival
        let best = isDeparture ? flight.bestDeparture : flight.bestArrival
        let changed = abs(best.timeIntervalSince(scheduled)) > 5 * 60

        return VStack(alignment: .leading, spacing: 12) {
            SectionHeader(title: isDeparture ? "Departure" : "Arrival",
                          systemImage: isDeparture ? "airplane.departure" : "airplane.arrival")
            HStack(alignment: .firstTextBaseline) {
                Text(iata).font(Theme.codeFont(28))
                Text(airport?.name ?? "")
                    .font(.system(size: 13, weight: .medium, design: .rounded))
                    .foregroundStyle(Theme.textSecondary)
                    .lineLimit(1)
            }
            HStack(spacing: 0) {
                StatBlock(caption: "Terminal",
                          value: (isDeparture ? flight.departureTerminal : flight.arrivalTerminal) ?? "—")
                StatBlock(caption: "Gate",
                          value: (isDeparture ? flight.departureGate : flight.arrivalGate) ?? "—",
                          color: Theme.accent)
                if !isDeparture {
                    StatBlock(caption: "Baggage", value: flight.baggageClaim ?? "—")
                }
                StatBlock(caption: changed ? "New time" : "Scheduled",
                          value: Fmt.time(best, airportIATA: iata),
                          color: changed ? Theme.orange : Theme.textPrimary)
            }
            if changed {
                InfoRow(label: "Originally scheduled",
                        value: Fmt.time(scheduled, airportIATA: iata),
                        valueColor: Theme.textTertiary)
            }
        }
        .cardStyle()
    }

    // MARK: Inbound aircraft ("Where's my plane")

    @ViewBuilder
    private func inboundCard(_ flight: Flight) -> some View {
        if let inbound = flight.inbound {
            VStack(alignment: .leading, spacing: 10) {
                SectionHeader(title: "Where's My Plane", systemImage: "location.viewfinder")
                HStack(spacing: 12) {
                    Image(systemName: "airplane.arrival")
                        .font(.title3)
                        .foregroundStyle(inbound.isDelayed ? Theme.orange : Theme.green)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("\(inbound.flightNumber) from \(inbound.originIATA)")
                            .font(.system(size: 14, weight: .bold, design: .rounded))
                        Text(inboundDetail(inbound, flight: flight))
                            .font(.system(size: 12, weight: .medium, design: .rounded))
                            .foregroundStyle(Theme.textSecondary)
                    }
                    Spacer()
                    if inbound.isDelayed {
                        StatusPill(text: "+\(inbound.delayMinutes)m", color: Theme.orange)
                    } else {
                        StatusPill(text: "On Time", color: Theme.green)
                    }
                }
            }
            .cardStyle()
        }
    }

    private func inboundDetail(_ inbound: InboundFlight, flight: Flight) -> String {
        let eta = inbound.estimatedArrival ?? inbound.scheduledArrival
        if eta > .now {
            return "Your aircraft arrives at \(flight.originIATA) \(Fmt.relative(eta))"
        }
        return "Your aircraft arrived at \(flight.originIATA) \(Fmt.relative(eta))"
    }

    // MARK: Aircraft

    @ViewBuilder
    private func aircraftCard(_ flight: Flight) -> some View {
        if flight.aircraftModel != nil || flight.registration != nil {
            VStack(alignment: .leading, spacing: 10) {
                SectionHeader(title: "Aircraft", systemImage: "airplane.circle")
                if let model = flight.aircraftModel {
                    InfoRow(label: "Type", value: model)
                }
                if let reg = flight.registration {
                    InfoRow(label: "Registration", value: reg)
                }
                if let origin = AirportDatabase.shared.airport(iata: flight.originIATA),
                   let dest = AirportDatabase.shared.airport(iata: flight.destinationIATA) {
                    InfoRow(label: "Route distance",
                            value: "\(Int(GreatCircle.distanceMiles(from: origin.coordinate, to: dest.coordinate))) mi")
                }
            }
            .cardStyle()
        }
    }

    // MARK: Weather

    @ViewBuilder
    private func weatherCards(_ flight: Flight) -> some View {
        if originMetar != nil || destinationMetar != nil {
            VStack(alignment: .leading, spacing: 10) {
                SectionHeader(title: "Weather", systemImage: "cloud.sun.fill")
                if let metar = originMetar {
                    weatherRow(iata: flight.originIATA, metar: metar)
                }
                if originMetar != nil && destinationMetar != nil {
                    Divider().overlay(Theme.separator)
                }
                if let metar = destinationMetar {
                    weatherRow(iata: flight.destinationIATA, metar: metar)
                }
            }
            .cardStyle()
        }
    }

    private func weatherRow(iata: String, metar: Metar) -> some View {
        HStack(spacing: 12) {
            Text(iata).font(Theme.codeFont(18))
            VStack(alignment: .leading, spacing: 2) {
                Text(metar.conditionsSummary ?? "Wind \(metar.windDescription)")
                    .font(.system(size: 13, weight: .bold, design: .rounded))
                Text("Vis \(metar.visibilityDescription) · Ceiling \(metar.ceilingDescription)")
                    .font(.system(size: 12, weight: .medium, design: .rounded))
                    .foregroundStyle(Theme.textSecondary)
            }
            Spacer()
            if let t = metar.tempF {
                Text("\(t)°")
                    .font(Theme.codeFont(20))
            }
            if let cat = metar.fltCat {
                StatusPill(text: cat, color: metar.flightCategoryColor)
            }
        }
    }

    // MARK: Data loading

    private func loadIntel(_ flight: Flight) async {
        signals = await FlightIntel.signals(for: flight)
        if let origin = AirportDatabase.shared.airport(iata: flight.originIATA) {
            originMetar = await WeatherService.shared.metar(for: origin)
        }
        if let dest = AirportDatabase.shared.airport(iata: flight.destinationIATA) {
            destinationMetar = await WeatherService.shared.metar(for: dest)
        }
    }
}
