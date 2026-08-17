# FlightDeck — Flighty-style iOS Flight Tracker: Build Plan

A personal-use iOS app recreating the core experience of Flighty Pro: live flight
tracking, Airport Intelligence, and a Connection Assistant — with a dark,
data-dense, Flighty-style UI. No social/collaborative features.

Legend: `[ ]` todo · `[x]` done

## Phase 0 — Research & decisions
- [x] Research Flighty Pro feature set (tracking timeline, delay signals, 25h
      "Where's my plane", Airport Intelligence, Connection Assistant ratings:
      relaxed / normal / tight / risky)
- [x] Choose data strategy: Demo Mode by default (zero config), real data via
      keyless public APIs (FAA NAS status, aviationweather.gov METAR, adsb.lol
      ADS-B) + optional AeroDataBox key for flight-number lookups
- [x] Choose stack: SwiftUI, iOS 17+, MapKit, zero third-party dependencies,
      Xcode 16 project with filesystem-synchronized groups

## Phase 1 — Project scaffolding
- [x] `plan.md` (this file)
- [x] Xcode project (`FlightDeck.xcodeproj`, synchronized folder target)
- [x] App entry point, root tab view (Flights · Airports · Connection · Settings)
- [x] Theme: dark palette, typography, reusable card/pill components

## Phase 2 — Models & data layer
- [x] `Flight` model (schedule/estimated/actual times, gates, terminals,
      baggage, aircraft, inbound flight, status phase, computed delay/progress)
- [x] `Airport` model + bundled `airports.json` database (~90 world airports:
      IATA/ICAO, coords, IANA timezone, minimum connection times, terminals)
- [x] `Metar` model (lenient decoding of aviationweather.gov JSON)
- [x] FAA airport event model (ground stops, ground delay programs,
      arrival/departure delays, closures)
- [x] `FlightDataProvider` protocol
- [x] `DemoFlightProvider` — realistic flights generated relative to *now*
      (one en-route, one boarding soon, a tight connection pair, one landed)
- [x] `AeroDataBoxProvider` — real flight status by number+date (RapidAPI key)
- [x] `FAAStatusService` — nasstatus.faa.gov XML (keyless)
- [x] `WeatherService` — METAR JSON (keyless)
- [x] `AdsbService` — live aircraft position by callsign (keyless)
- [x] `FlightStore` (persistence to JSON in Application Support) +
      `SettingsStore` (demo mode, API key)

## Phase 3 — My Flights (core tracking)
- [x] Flight list: Today / Upcoming / Past sections, Flighty-style cards
      (airline monogram, big airport codes, live progress bar, status pill,
      delay-aware times)
- [x] Add flight: flight number + date lookup (demo or AeroDataBox), plus
      one-tap sample trip in demo mode
- [x] Flight detail: map header with great-circle route + live plane position,
      status banner, event timeline (gate close → takeoff → landing → baggage),
      departure/arrival cards (terminal/gate/baggage, sched vs est vs actual),
      aircraft card, "Where's my plane" inbound row, weather at both ends
- [x] Delay intel heuristics: late inbound aircraft, FAA program at
      origin/destination, IFR weather — surfaced as "FlightIntel" signals
- [x] Pull-to-refresh + auto-refresh of live flights

## Phase 4 — Airport Intelligence
- [x] Airport search/browse (bundled DB), favorites
- [x] Airport detail: huge code header, local time, FAA delay status card with
      plain-English reason + severity color, decoded METAR card (flight
      category VFR/MVFR/IFR/LIFR, wind, visibility, ceiling, temp), map, facts
      (terminals, minimum connection times)
- [x] Non-US airports: weather-only intelligence (FAA feed is US-only)

## Phase 5 — Connection Assistant (barebones-but-useful)
- [x] Auto-detect connection pairs in saved flights (arrival airport ==
      next departure airport, within 24 h)
- [x] Manual pairing of any two saved flights
- [x] Risk engine: live layover minutes (estimated times, not scheduled) vs
      airport minimum connection time → RISKY / TIGHT / NORMAL / RELAXED,
      domestic vs international MCT, terminal-change penalty
- [x] Connection view: countdown, risk pill, arrival gate → departure gate,
      what-changed explanation, misconnect warning

## Phase 6 — Polish & docs
- [x] Settings: demo mode toggle, AeroDataBox key entry, data attribution
- [x] App icon + accent color
- [x] README: full feature tour, architecture decisions, API setup, and
      step-by-step "run it on your iPhone" guide
- [x] Final review pass over all Swift files (API misuse, decoding safety)
- [x] Commit + push

## Phase 7 — Live traffic & smooth aircraft motion
Research and design in [`docs/live-traffic-plan.md`](docs/live-traffic-plan.md).
- [x] Fix latent ADS-B bug: surface aircraft report `true_heading`, not `track`,
      so tracked planes silently lost their rotation on touchdown
- [x] `TrafficService` — adsb.lol radius search; `TrafficReport` model with
      NACp-derived accuracy and lenient per-aircraft decoding
- [x] `DeadReckoning` — kinematic state, WGS-84 forward projection, easing
      reconciliation, shortest-path heading blend, staleness caps
- [x] `TrafficStore` / `AircraftTracker` — polling, reconciliation, grace-period
      removal; stop on background, halve rate in Low Power Mode
- [x] `LiveTrafficMapView` — one display-clock-driven `Canvas` overlay rather
      than per-aircraft annotations; altitude colouring, stale fading,
      collision-avoided labels, confidence ring for own aircraft
- [x] Airport ground view (queue-readable at 3 nm) and traffic near own aircraft
- [x] Verified in simulator; engine covered by 24 checks

## Phase 8 — Passport, flight-centric tracking & arrival forecast
Research in [`docs/flighty-research.md`](docs/flighty-research.md) (what the
real Flighty ships, what we matched, and the gaps left on purpose).

- [x] Research pass over Flighty's Passport, delay prediction and map UX
- [x] `Flight`: seat field, DOT 15-minute delay threshold, archival clock,
      origin-timezone calendar, route distance, trip-shape predicates
- [x] `PassportStats` — one pure fold over the flight log producing flights,
      miles, air time, airports, countries, airlines, aircraft types, tail
      numbers, seats, routes, records, trip shape and the full delay tracker
- [x] Passport tab: headline tiles, frequency-weighted route map, delay
      tracker (hours lost, on-time rate, worst delay, worst airlines and
      arrival airports), most-flown aircraft, ranked lists, day-of-week
      histogram, records
- [x] Past Flights: month-grouped, searchable; flights archive themselves
      30 minutes after landing, driven by a 30-second clock on `FlightStore`
      so the move happens live rather than on relaunch
- [x] `FlightTrackingMapView` — tracking now hangs off *the flight*: own
      aircraft on its great-circle route, no zoom ceiling, surrounding ADS-B
      traffic both airborne and on the ground, Ground/Nearby/Route scopes,
      tap-to-identify, zoom-preserving follow mode
- [x] Fix tracker lifetime: `FlightMapView` no longer stops the poll in
      `onDisappear`, which was killing the live track the moment the user
      pushed the tracking map
- [x] `DelayHistoryStore` — rolling 60-day punctuality record, de-duplicated
      by leg and day, fed by flights flown plus a per-route backfill
- [x] `DelayHistoryBackfill` — sequential provider scan with a real key;
      deterministic seeded synthetic history in Demo Mode, labelled as such
- [x] `ArrivalForecaster` — hierarchical shrinkage over five tiers of history,
      log-odds adjustments for live conditions, live-estimate takeover once
      airborne, with sample size and every contributing factor surfaced
- [x] `docs/simulator-test-plan.md` — manual test script for a local session
      with the iOS simulator
- [x] `.claude/skills/flightdeck/SKILL.md` — orientation for future sessions
- [ ] **Build and run in the simulator** — this phase was written in an
      environment with no Swift toolchain and has never been compiled

## Explicitly out of scope
- Flighty Friends / social features, shared trips
- Push notifications (needs paid Apple Developer account + server); delay
  signals are computed in-app on refresh instead
- Shareable Passport cards (the value is social; this app has no social surface)
- Seat maps, TripIt/calendar import, Live Activities (noted as future ideas)
- Airframe age and "Get Me Off This Plane" taxi-in time — no bundled data
  source for either
