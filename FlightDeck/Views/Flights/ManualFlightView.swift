import SwiftUI

/// Type a flight in by hand.
///
/// This exists because live schedule feeds are narrower than people's plans.
/// AeroDataBox's status endpoint covers about a week either side of today, so
/// a flight booked for next February can't be looked up at all — and until now
/// that was simply a dead end with a red error under the search button.
///
/// Two things make it less tedious than it sounds:
///
/// * The route and airline are prefilled from `FlightRouteService`, which is
///   keyless and global, so "BA137" arrives already knowing it's British
///   Airways and which city pair it flies.
/// * Times are entered as **local wall clock at each airport**, the way a
///   ticket prints them, and the arrival date is worked out rather than asked
///   for — an overnight leg resolves to the next day on its own.
struct ManualFlightView: View {
    @EnvironmentObject private var store: FlightStore
    @Environment(\.dismiss) private var dismiss

    /// Prefill from whatever the search screen already knows.
    var designator: String = ""
    var route: FlightRouteService.Route?
    var departureDate: Date = .now
    /// Lets the presenting screen close itself too — this is usually opened
    /// from Add Flight, and dismissing only this sheet leaves the user staring
    /// at the search form instead of the flight they just added.
    var onAdded: () -> Void = {}

    @State private var airlineCode = ""
    @State private var flightNumber = ""
    @State private var originIATA = ""
    @State private var destinationIATA = ""
    @State private var departureDay = Date.now
    @State private var departureTime = Date.now
    @State private var arrivalTime = Date.now
    @State private var terminal = ""
    @State private var gate = ""
    @State private var didPrefill = false

    var body: some View {
        NavigationStack {
            Form {
                flightSection
                routeSection
                timesSection
                groundSection
            }
            .navigationTitle("Add Manually")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Add") { addFlight() }
                        .fontWeight(.bold)
                        .disabled(!isValid)
                }
            }
            .onAppear(perform: prefill)
        }
        .preferredColorScheme(.dark)
    }

    // MARK: - Sections

    private var flightSection: some View {
        Section {
            HStack {
                TextField("BA", text: $airlineCode)
                    .font(Theme.monoFont(17))
                    .textInputAutocapitalization(.characters)
                    .autocorrectionDisabled()
                    .frame(width: 60)
                Divider().overlay(Theme.separator)
                TextField("137", text: $flightNumber)
                    .font(Theme.monoFont(17))
                    .keyboardType(.numberPad)
            }
        } header: {
            Text("Flight")
        } footer: {
            if let route, let airline = route.airlineName {
                Text("\(airline), from the keyless route database.")
            }
        }
    }

    private var routeSection: some View {
        Section {
            airportField("From", text: $originIATA)
            airportField("To", text: $destinationIATA)
        } header: {
            Text("Route")
        } footer: {
            Text(routeFooter)
        }
    }

    private var timesSection: some View {
        Section {
            DatePicker("Departure date", selection: $departureDay, displayedComponents: .date)
            DatePicker("Departs (\(originLabel) time)",
                       selection: $departureTime, displayedComponents: .hourAndMinute)
            DatePicker("Arrives (\(destinationLabel) time)",
                       selection: $arrivalTime, displayedComponents: .hourAndMinute)
        } header: {
            Text("Times")
        } footer: {
            Text(timesFooter)
        }
    }

    private var groundSection: some View {
        Section("Gate (optional)") {
            TextField("Terminal", text: $terminal)
                .textInputAutocapitalization(.characters)
                .autocorrectionDisabled()
            TextField("Gate", text: $gate)
                .textInputAutocapitalization(.characters)
                .autocorrectionDisabled()
        }
    }

    private func airportField(_ label: String, text: Binding<String>) -> some View {
        HStack {
            Text(label)
            Spacer()
            TextField("IATA", text: text)
                .font(Theme.codeFont(20))
                .multilineTextAlignment(.trailing)
                .textInputAutocapitalization(.characters)
                .autocorrectionDisabled()
                .frame(width: 90)
                .onChange(of: text.wrappedValue) { _, newValue in
                    // Three letters is the whole format; trimming as they type
                    // beats validating after the fact.
                    let cleaned = newValue.uppercased().filter(\.isLetter)
                    if cleaned != newValue { text.wrappedValue = String(cleaned.prefix(3)) }
                    else if cleaned.count > 3 { text.wrappedValue = String(cleaned.prefix(3)) }
                }
        }
    }

    // MARK: - Copy

    private var originLabel: String { originIATA.isEmpty ? "local" : originIATA }
    private var destinationLabel: String { destinationIATA.isEmpty ? "local" : destinationIATA }

    private var routeFooter: String {
        let missing = [originIATA, destinationIATA]
            .filter { $0.count == 3 && AirportDatabase.shared.airport(iata: $0) == nil }
        guard !missing.isEmpty else {
            return route == nil
                ? "Three-letter IATA codes."
                : "Prefilled from the route database — it knows the route this flight number usually flies, so check it's the leg you're on."
        }
        // Being explicit beats silently using the phone's timezone and
        // quietly dropping the flight out of the Passport's mileage.
        return "\(missing.joined(separator: ", ")) isn't in the bundled airport database, so times will use your phone's timezone and this flight won't count toward Passport distance."
    }

    private var timesFooter: String {
        guard isValid else { return "Enter times as they're printed on your ticket — local at each airport." }
        let departure = resolvedDeparture
        let arrival = resolvedArrival(after: departure)
        return "Enter times as printed on your ticket, local at each airport. That works out to \(Fmt.duration(arrival.timeIntervalSince(departure))) in the air"
            + (Calendar.current.isDate(departure, inSameDayAs: arrival) ? "." : ", arriving the next day.")
    }

    // MARK: - Building the flight

    private var isValid: Bool {
        !airlineCode.isEmpty
            && !flightNumber.isEmpty
            && originIATA.count == 3
            && destinationIATA.count == 3
            && originIATA != destinationIATA
    }

    private func timeZone(for iata: String) -> TimeZone {
        AirportDatabase.shared.airport(iata: iata)?.timeZone ?? .current
    }

    /// The picked day and the picked time-of-day, reassembled as a wall clock
    /// in the origin airport's zone. `DatePicker` hands back instants in the
    /// phone's zone; taking its components and rebuilding them elsewhere is
    /// what makes "11:05 at SFO" mean 11:05 at SFO from anywhere on earth.
    private var resolvedDeparture: Date {
        var phone = Calendar(identifier: .gregorian)
        phone.timeZone = .current
        let day = phone.dateComponents([.year, .month, .day], from: departureDay)
        let time = phone.dateComponents([.hour, .minute], from: departureTime)

        var origin = Calendar(identifier: .gregorian)
        origin.timeZone = timeZone(for: originIATA)
        return origin.date(from: DateComponents(year: day.year,
                                                month: day.month,
                                                day: day.day,
                                                hour: time.hour,
                                                minute: time.minute)) ?? departureDay
    }

    /// The first instant strictly after departure whose destination-local wall
    /// clock matches what was entered. Overnight legs fall out for free, with
    /// no "does it land the next day?" switch to get wrong.
    private func resolvedArrival(after departure: Date) -> Date {
        var phone = Calendar(identifier: .gregorian)
        phone.timeZone = .current
        let time = phone.dateComponents([.hour, .minute], from: arrivalTime)

        var destination = Calendar(identifier: .gregorian)
        destination.timeZone = timeZone(for: destinationIATA)
        return destination.nextDate(after: departure,
                                    matching: DateComponents(hour: time.hour, minute: time.minute),
                                    matchingPolicy: .nextTime)
            ?? departure.addingTimeInterval(2 * 3600)
    }

    private func addFlight() {
        let departure = resolvedDeparture
        let arrival = resolvedArrival(after: departure)
        let code = airlineCode.uppercased()

        var flight = Flight(
            airlineName: route?.airlineName ?? DemoFlightProvider.airlineName(for: code),
            airlineCode: code,
            flightNumber: flightNumber,
            // Enough for adsb.lol to find the airframe once it's flying, when
            // the route database knew the ICAO form.
            callSign: route?.callsignICAO.isEmpty == false ? route?.callsignICAO : nil,
            originIATA: originIATA.uppercased(),
            destinationIATA: destinationIATA.uppercased(),
            scheduledDeparture: departure,
            scheduledArrival: arrival,
            departureTerminal: terminal.isEmpty ? nil : terminal.uppercased(),
            departureGate: gate.isEmpty ? nil : gate.uppercased(),
            arrivalTerminal: nil,
            arrivalGate: nil,
            baggageClaim: nil,
            aircraftModel: nil,
            registration: nil)
        // Hand-entered: nothing here came from a provider, so refresh must not
        // pretend it can update it.
        flight.isLiveData = false
        store.add(flight)
        onAdded()
        dismiss()
    }

    private func prefill() {
        guard !didPrefill else { return }
        didPrefill = true

        if let parsed = DemoFlightProvider.parseDesignator(designator) {
            airlineCode = parsed.code
            flightNumber = parsed.number
        } else if let iata = route?.callsignIATA,
                  let parsed = DemoFlightProvider.parseDesignator(iata) {
            airlineCode = parsed.code
            flightNumber = parsed.number
        }
        if let route {
            originIATA = route.origin.iata
            destinationIATA = route.destination.iata
        }

        departureDay = departureDate
        // A sensible mid-morning default beats "right now", which is almost
        // never the answer and is the value most likely to be left in by
        // accident.
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .current
        departureTime = calendar.date(bySettingHour: 9, minute: 0, second: 0, of: departureDate) ?? departureDate
        arrivalTime = calendar.date(bySettingHour: 12, minute: 0, second: 0, of: departureDate) ?? departureDate
    }
}
