# ✈️ FlightDeck

A personal-use iOS flight tracker inspired by **Flighty Pro** — its core flight
tracking experience, **Airport Intelligence**, and **Connection Assistant** —
rebuilt from scratch in SwiftUI with a dark, data-dense, Flighty-style UI.

No social features, no accounts, no subscriptions. Just useful flight
information for you.

> **Naming note:** "Flighty" is a trademark of Flighty LLC, and this repo
> contains no Flighty code or artwork. FlightDeck is an original,
> feature-inspired implementation for personal use, with its own name, icon,
> and design system.

Built against the checklist in [`plan.md`](plan.md).

---

## What's in the app

### 1. My Flights (core tracking)
- **Flighty-style flight cards**: airline monogram, big rounded airport codes,
  a live progress bar with a plane glyph, status pill (On Time / Boarding /
  En Route / Late / Arrived / Cancelled), and delay-aware times — the original
  time shown struck-through next to the new estimate, in the *airport's*
  local timezone (not your phone's).
- **Flight detail page**:
  - Map header with the **great-circle route** drawn as a dashed arc and the
    aircraft's position — live ADS-B position when tracking real flights,
    otherwise interpolated along the route from time progress.
  - Color-coded **status banner** ("En route to JFK · lands in 2h 5m").
  - **Flight Intel** — heuristic delay signals (see below).
  - **Timeline**: boarding → departure → arrival → baggage, with gate/claim
    numbers and check-off state as events pass.
  - **Departure & arrival cards**: terminal, gate, baggage, scheduled vs.
    latest times.
  - **"Where's My Plane"**: the inbound flight bringing your aircraft, with
    its origin and delay status — a late inbound is the #1 predictor of a
    late departure.
  - **Aircraft card**: type, registration, route distance.
  - **Weather at both ends**: decoded METARs with VFR/MVFR/IFR/LIFR pills.
- **Add flights** by designator + date ("DL 482"), pull-to-refresh, and
  auto-refresh of active flights every 90 seconds while the app is open.

### 2. Airport Intelligence
- Searchable database of **110 major world airports** (bundled offline).
- Rows badge airports that currently have live FAA alerts.
- Airport page:
  - **Live Status** — FAA ground stops, ground delay programs,
    departure/arrival delays, and closures, translated into plain English
    with the cause ("Departures delayed 45 min. Cause: weather —
    thunderstorms.") and severity colors. US airports only (that's where the
    public feed exists); non-US airports say so honestly.
  - **Weather** — decoded METAR: flight category pill, temperature, wind,
    visibility, ceiling, and the raw METAR string for avgeeks.
  - Satellite map, local time, terminal overview, and the airport's minimum
    connection times.
- Favorites (star an airport to pin it).

### 3. Connection Assistant
- **Auto-detects connections** in your tracked flights (leg 1 arrives where
  leg 2 departs within 24 h) and preselects the first one.
- Or manually pair any two flights.
- Rates the connection **RELAXED / NORMAL / TIGHT / RISKY / MISCONNECT**
  using *live estimated times* (not the schedule), the connecting airport's
  minimum connection time (domestic vs. international ruleset, from the
  bundled database), and a +15 min penalty when you change terminals.
- Shows the live layover countdown, arrival gate → departure gate, minutes
  of buffer lost/gained vs. schedule, and what to do about it.

### 4. Flight Intel (delay signals)
A lightweight, transparent take on Flighty's ML delay predictions. On each
refresh the app gathers the same classes of evidence Flighty advertises and
surfaces them as signals with severity colors:
1. **Late inbound aircraft** ("your plane hasn't arrived yet, running 38 min late").
2. **FAA programs** at your origin or destination (ground stop, ground delay
   program, delays, closure) with the FAA's stated cause.
3. **IFR/LIFR weather** at either end (low ceilings/visibility → reduced
   arrival rates).
4. **Confirmed schedule slips** from the data provider.

It's heuristic rather than ML, but it's built from the real leading
indicators, refreshes live, and explains itself.

---

## Data sources & Demo Mode

The app is designed to be useful **with zero configuration** and to use
**free, keyless public APIs** wherever possible:

| Data | Source | Key needed? |
|---|---|---|
| Airport delay programs (US) | FAA NAS Status — `nasstatus.faa.gov` | No |
| Weather (METAR, worldwide) | NOAA/NWS — `aviationweather.gov` | No |
| Live aircraft positions | `api.adsb.lol` (community ADS-B) | No |
| Airport database | Bundled `airports.json` (curated, offline) | No |
| Flight schedules & status | **Demo Mode** (default) or **AeroDataBox** | AeroDataBox: free RapidAPI key |

**Demo Mode** (default: on) generates a realistic sample itinerary *relative
to the current clock* — one flight in the air right now, a JFK→LHR connection
later today (so the Connection Assistant has something to chew on), tomorrow's
flight, and a completed one. Statuses evolve as real time passes. Airport
Intelligence and weather are **always real** — they're keyless.

**Real flight tracking**: create a free account at
[rapidapi.com](https://rapidapi.com), subscribe to **AeroDataBox** (Basic
plan is free with a monthly request quota), paste your key into
**Settings → Live flight lookups**, and switch Demo Mode off. Now "Add
Flight" resolves real flights with gates, terminals, aircraft, and revised
times, and the map uses live ADS-B positions via the flight's callsign.

---

## Architecture

```
FlightDeck/
├── FlightDeckApp.swift          App entry; injects the two stores
├── RootTabView.swift            Flights · Airports · Connection · Settings
├── Theme/Theme.swift            Design tokens (colors, type, card style)
├── Models/                      Flight, Airport, Metar, AirportEvent,
│                                ConnectionAssessment (+ risk engine)
├── Services/
│   ├── FlightDataProvider.swift  Protocol: where schedules come from
│   ├── DemoFlightProvider.swift   Clock-relative simulated flights
│   ├── AeroDataBoxProvider.swift  Real lookups (RapidAPI)
│   ├── FAAStatusService.swift     Keyless FAA NAS status (XML), cached
│   ├── WeatherService.swift       Keyless METARs (JSON), cached
│   ├── AdsbService.swift          Keyless live positions by callsign
│   ├── FlightIntel.swift          Delay-signal heuristics
│   └── AirportDatabase.swift      Bundled airports.json loader
├── Stores/
│   ├── FlightStore.swift          Source of truth + persistence + refresh
│   └── SettingsStore.swift        Demo mode, API key, favorites
├── Utilities/                     Great-circle math, formatters
├── Views/                         Flights / Airports / Connection /
│                                  Settings / shared components
└── Resources/airports.json        110 airports: coords, IANA tz, MCTs
```

### Key decisions (and why)

- **SwiftUI, iOS 17+, zero third-party dependencies.** Nothing to resolve or
  update — open the project and press Run. MapKit's SwiftUI API
  (`Map`/`MapPolyline`/`Annotation`, iOS 17) draws the route map natively.
- **Provider protocol between UI and data.** `FlightDataProvider` is the seam:
  `DemoFlightProvider` and `AeroDataBoxProvider` are interchangeable, and the
  UI never knows which is active. Adding FlightAware/OAG later = one file.
- **Demo Mode is generated in code, not fixture JSON**, and always relative to
  `Date.now`. Fixture files with hardcoded dates rot; a generated itinerary
  demos every feature (live progress, delays, connections) forever.
- **Keyless intelligence, keyed schedules.** Airport status, weather, and
  ADS-B positions are public feeds — so the app's most distinctive features
  (Airport Intelligence, Flight Intel) work with no signup at all. Only
  per-flight schedule lookups need a key, because no keyless source exists.
- **Times are stored as absolute `Date`s and rendered in the airport's
  timezone** via the bundled IANA identifiers. This is the single most common
  flight-app bug class (a 7 AM departure showing as 4 AM because your phone
  is in a different zone), designed out at the model layer:
  `Flight` holds UTC instants; `Fmt.time(_:airportIATA:)` does the rest.
- **Lenient decoding at every API boundary.** Real aviation feeds mix types
  (`visib: "10+"` vs `6.0`, `wdir: "VRB"` vs `240`, `alt_baro: "ground"` vs
  `35000`). A `FlexibleValue` enum decodes number-or-string, every field is
  optional, and network/parse failures degrade to "no data" rather than
  errors. The FAA XML is parsed with a small tolerant state machine.
- **Heuristic intel, honestly labeled.** Flighty's delay predictions are an
  ML model trained on years of data; recreating that isn't feasible for a
  personal app. Instead, the same *inputs* (late inbound, FAA programs,
  IFR weather) are surfaced as explainable signals — arguably more useful
  for one person than a black-box probability.
- **Connection risk = live times vs. per-airport MCT.** The bundled database
  carries rule-of-thumb minimum connection times (domestic/international) per
  airport; the assessment recomputes from *estimated* times on every refresh,
  applies the international ruleset when a leg crosses a border, and adds a
  terminal-change penalty. Thresholds: below MCT → **Risky**, within
  +30 min → **Tight**, +90 → **Normal**, beyond → **Relaxed**, and negative
  layover → **Misconnect**.
- **Persistence is a JSON file** in Application Support (ISO-8601 dates).
  For dozens of flights, SwiftData/Core Data would be ceremony without
  benefit; a file you can inspect wins.
- **Xcode 16 "synchronized folder" project format.** The `.pbxproj` doesn't
  enumerate source files — the `FlightDeck/` folder *is* the target — so
  adding files never breaks the project, and the project file is 300 lines
  instead of 3,000.
- **Trade-offs accepted:** API key in UserDefaults rather than Keychain
  (personal app, no dependencies); no push notifications (needs a paid Apple
  Developer account + a server watching your flights — in-app refresh covers
  the personal-use case); FAA feed means airport *delay programs* are US-only
  (weather intelligence remains worldwide).

### Ideas for later
Live Activities / Dynamic Island for the lock screen, WidgetKit widgets,
Keychain for the key, seat-map links, calendar import, a Watch app.

---

## Get it running on your iPhone

You need a Mac with **Xcode 16 or newer** (free) and an iPhone on **iOS 17+**.
No paid Apple Developer account required.

1. **Clone and open**
   ```bash
   git clone <this repo>
   cd flighty-pro
   open FlightDeck.xcodeproj
   ```

2. **Set your signing team** (one-time)
   - Click the blue **FlightDeck** project icon in the sidebar → target
     **FlightDeck** → **Signing & Capabilities** tab.
   - Check **Automatically manage signing**, then choose your **Team** —
     with a free Apple ID, add it under Xcode → Settings → Accounts and pick
     the "(Personal Team)" entry.
   - If the bundle identifier collides, change `com.personal.flightdeck` to
     anything unique (e.g. `com.yourname.flightdeck`).

3. **Plug in your iPhone** with a cable (or set up Wi-Fi debugging).
   - On the phone: **Settings → Privacy & Security → Developer Mode → On**
     (it appears after Xcode talks to the phone once; requires a restart).
   - Select your iPhone in Xcode's device dropdown (top toolbar).

4. **Run**: press **⌘R**. First run only, the phone will block the app —
   go to **Settings → General → VPN & Device Management**, tap your Apple ID,
   and **Trust** it. Launch again.

5. **Explore**: the app opens in Demo Mode with a sample trip. Check the
   en-route flight's detail page, open **Airports → ATL or EWR** for live FAA
   status, and the **Connection** tab for the JFK layover analysis.

6. **(Optional) Real data**: get a free AeroDataBox key on RapidAPI, paste it
   in **Settings**, toggle Demo Mode off, and add your next real flight by
   number.

> **Free-account caveat:** apps signed with a free Personal Team expire after
> 7 days — just press ⌘R again to reinstall. A paid developer account ($99/yr)
> extends this to a year.

### Simulator
Everything except live ADS-B positions is equally happy in the iOS Simulator:
choose any iPhone simulator instead of a device and press ⌘R.

---

## Attribution
- Airport delay data: [FAA National Airspace System Status](https://nasstatus.faa.gov)
- Weather: [NOAA Aviation Weather Center](https://aviationweather.gov)
- Live positions: [adsb.lol](https://adsb.lol) community ADS-B network
- Optional schedules: [AeroDataBox](https://aerodatabox.com)
- Inspiration: [Flighty](https://flighty.com) — go buy it, it's excellent.
