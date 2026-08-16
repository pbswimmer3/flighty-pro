import SwiftUI

/// Full flight page: live map header that opens into tracking, status banner,
/// arrival forecast, delay-intel signals, event timeline, departure/arrival
/// cards, aircraft, inbound plane, weather.
struct FlightDetailView: View {
    @EnvironmentObject private var store: FlightStore
    @EnvironmentObject private var settings: SettingsStore
    @EnvironmentObject private var history: DelayHistoryStore
    let flightID: UUID

    @State private var signals: [IntelSignal] = []
    @State private var originMetar: Metar?
    @State private var destinationMetar: Metar?
    @State private var originEvents: [AirportEvent] = []
    @State private var destinationEvents: [AirportEvent] = []
    @State private var forecast: ArrivalForecast?
    @State private var isBuildingForecast = false
    @State private var seatDraft = ""
    /// Owned here so the map header, the tracking screen and the traffic view
    /// all read the same live track — and so the poll is cancelled when this
    /// page is popped, not when it's merely covered by a pushed view.
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
                mapHeader(flight)
                statusBanner(flight)
                forecastCard(flight)
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
            seatDraft = flight.seat ?? ""
            await loadIntel(flight)
            await backfillHistory(flight)
            rebuildForecast(flight)
        }
        .onDisappear { commitSeat(flight) }
    }

    // MARK: - Map header → tracking

    /// The map is the entry point to tracking. Tapping the flight gets you to
    /// your aircraft on its route; you never have to go via an airport page.
    private func mapHeader(_ flight: Flight) -> some View {
        NavigationLink {
            FlightTrackingMapView(flight: flight, tracker: tracker)
        } label: {
            ZStack(alignment: .bottomTrailing) {
                FlightMapView(flight: flight, tracker: tracker)
                    .frame(height: 260)
                    .allowsHitTesting(false)   // the whole header is one tap target

                HStack(spacing: 6) {
                    Image(systemName: "dot.radiowaves.up.forward")
                        .font(.system(size: 11, weight: .bold))
                    Text(trackingPrompt(flight))
                        .font(.system(size: 12, weight: .heavy, design: .rounded))
                    Image(systemName: "chevron.right")
                        .font(.system(size: 10, weight: .bold))
                }
                .foregroundStyle(.white)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(Theme.accent.opacity(0.92), in: Capsule())
                .padding(12)
            }
            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    private func trackingPrompt(_ flight: Flight) -> String {
        if tracker.track != nil { return "Track live · traffic around you" }
        if flight.effectivePhase.isAirborne { return "Track this flight" }
        if flight.effectivePhase.isComplete { return "See traffic at \(flight.destinationIATA)" }
        return "See traffic at \(flight.originIATA)"
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

    // MARK: Arrival forecast

    @ViewBuilder
    private func forecastCard(_ flight: Flight) -> some View {
        if let forecast {
            ArrivalForecastCard(flight: flight, forecast: forecast)
        } else if isBuildingForecast {
            HStack(spacing: 10) {
                ProgressView()
                Text("Building arrival forecast from the last \(DelayObservation.analysisWindowDays) days…")
                    .font(.system(size: 13, weight: .medium, design: .rounded))
                    .foregroundStyle(Theme.textSecondary)
            }
            .cardStyle()
        }
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

    private func aircraftCard(_ flight: Flight) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionHeader(title: "Aircraft", systemImage: "airplane.circle")
            if let model = flight.aircraftType {
                InfoRow(label: "Type", value: model)
            }
            if let reg = flight.tailNumber {
                InfoRow(label: "Registration", value: reg)
            }
            if let origin = AirportDatabase.shared.airport(iata: flight.originIATA),
               let dest = AirportDatabase.shared.airport(iata: flight.destinationIATA) {
                InfoRow(label: "Route distance",
                        value: "\(Fmt.grouped(GreatCircle.distanceMiles(from: origin.coordinate, to: dest.coordinate))) mi")
            }

            // Seat is the one detail no provider knows, and the Passport's
            // "top seat" stat is only as good as what gets typed here.
            HStack {
                Text("Seat")
                    .font(.system(size: 14, weight: .medium, design: .rounded))
                    .foregroundStyle(Theme.textSecondary)
                Spacer()
                TextField("Add", text: $seatDraft)
                    .font(.system(size: 15, weight: .bold, design: .rounded))
                    .multilineTextAlignment(.trailing)
                    .textInputAutocapitalization(.characters)
                    .autocorrectionDisabled()
                    .frame(width: 90)
                    .onSubmit { commitSeat(flight) }
            }
            .padding(.vertical, 2)
        }
        .cardStyle()
    }

    private func commitSeat(_ flight: Flight) {
        let trimmed = seatDraft.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        guard trimmed != (flight.seat ?? "") else { return }
        store.setSeat(trimmed, for: flight)
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

    // MARK: - Data loading

    private func loadIntel(_ flight: Flight) async {
        signals = await FlightIntel.signals(for: flight)

        if let origin = AirportDatabase.shared.airport(iata: flight.originIATA) {
            originMetar = await WeatherService.shared.metar(for: origin)
            originEvents = origin.isUS ? await FAAStatusService.shared.events(for: origin.iata) : []
        }
        if let dest = AirportDatabase.shared.airport(iata: flight.destinationIATA) {
            destinationMetar = await WeatherService.shared.metar(for: dest)
            destinationEvents = dest.isUS ? await FAAStatusService.shared.events(for: dest.iata) : []
        }
        rebuildForecast(flight)
    }

    /// Pull recent punctuality for this route into the history store so the
    /// forecast has something to work from. Cheap on repeat visits: the store
    /// remembers when a route was last scanned.
    private func backfillHistory(_ flight: Flight) async {
        guard !flight.hasFlown(), flight.phase != .cancelled else { return }
        guard history.needsBackfill(originIATA: flight.originIATA,
                                    destinationIATA: flight.destinationIATA) else { return }

        isBuildingForecast = true
        defer { isBuildingForecast = false }

        let isDemo = settings.demoMode || settings.aeroDataBoxKey.isEmpty
        let backfill = DelayHistoryBackfill(provider: settings.provider, isDemo: isDemo)
        let observations = await backfill.observations(for: flight)
        guard !Task.isCancelled else { return }

        history.ingest(observations)
        history.markBackfilled(originIATA: flight.originIATA,
                               destinationIATA: flight.destinationIATA)
    }

    private func rebuildForecast(_ flight: Flight) {
        let context = ForecastContext(
            inboundDelayMinutes: flight.inbound?.delayMinutes ?? 0,
            originEvents: originEvents,
            destinationEvents: destinationEvents,
            originIsIFR: isLowVisibility(originMetar),
            destinationIsIFR: isLowVisibility(destinationMetar))

        forecast = ArrivalForecaster.forecast(for: flight,
                                              history: history.window(),
                                              context: context)
    }

    private func isLowVisibility(_ metar: Metar?) -> Bool {
        guard let category = metar?.fltCat?.uppercased() else { return false }
        return category == "IFR" || category == "LIFR"
    }
}
