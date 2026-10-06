---
name: flightdeck
description: Orientation for the FlightDeck iOS app (SwiftUI flight tracker in this repo) — architecture, data flow, the Passport/delay-forecast/live-tracking subsystems, invariants that are easy to break, and how to build and test. Use whenever working on anything under FlightDeck/, the Xcode project, or questions about how this app tracks flights, computes stats, or forecasts arrivals.
---

# FlightDeck

A personal-use iOS flight tracker in the spirit of Flighty Pro. SwiftUI,
iOS 17+, MapKit, **zero third-party dependencies**, no backend.

Not affiliated with Flighty. Ships no Flighty artwork or code.

## Reading order for a cold start

1. This file.
2. `plan.md` — phase-by-phase build log, and the explicit non-goals.
3. `docs/flighty-research.md` — what the real Flighty does, what we matched,
   and the gaps we left on purpose.
4. `docs/live-traffic-plan.md` — the dead-reckoning design behind smooth
   aircraft motion.
5. `docs/simulator-test-plan.md` — manual test script for the iOS simulator.

## Build & run

```
open FlightDeck.xcodeproj      # Xcode 16+
```

The target uses a **filesystem-synchronized root group**, so any `.swift` file
added anywhere under `FlightDeck/` is compiled automatically — never edit
`project.pbxproj` to add a file.

There is no test target and no CI. Verification is: build for an iOS 17+
simulator, then walk `docs/simulator-test-plan.md`.

**Demo Mode is on by default** and needs no API key, so the whole app is
exercisable on a fresh install.

## Architecture

```
FlightDeck/
  Models/       value types + pure computation (Flight, Airport, Metar,
                TrafficReport, PassportStats, DelayObservation, AirportEvent)
  Services/     stateless I/O and algorithms (providers, ADS-B, FAA, METAR,
                FlightIntel, ArrivalForecaster, DelayHistoryBackfill)
  Stores/       @MainActor ObservableObjects owning app state
                (FlightStore, SettingsStore, DelayHistoryStore,
                 TrafficStore, AircraftTracker)
  Views/        SwiftUI, grouped by tab
  Utilities/    GreatCircle, DeadReckoning, Fmt
  Theme/        design tokens; dark, data-dense, heavy rounded type
```

Three `@EnvironmentObject`s are injected at the root in `FlightDeckApp`:
`SettingsStore`, `FlightStore`, `DelayHistoryStore`. Anything reading flights or
history must have all of them in scope, including in `#Preview`s.

Tabs: **Flights · Passport · Airports · Connection · Settings**.

### Data sources

| Source | Key? | Used for |
|---|---|---|
| `DemoFlightProvider` | none | Demo Mode — flights generated relative to *now* |
| AeroDataBox (RapidAPI) | yes | Real schedules and status |
| adsb.lol | none | Live aircraft positions, radius traffic search |
| adsbdb.com | none | Callsign → route + airline (`FlightRouteService`) |
| FAA NAS Status | none | Ground stops / delay programs (US only) |
| aviationweather.gov | none | METAR |

`SettingsStore.provider` picks Demo vs AeroDataBox. Demo Mode is treated as
"on" whenever `demoMode` is set **or** the key is empty.

**AeroDataBox's status endpoint only reaches ±7 days**
(`AeroDataBoxProvider.scheduleHorizonDays`). Anything outside that is rejected
before the request with `.dateOutOfRange` — it used to come back as a 2xx whose
body wasn't a flight list, and surfaced as an unreadable "unexpected response".
The provider now also accepts both the bare-array and `{"flights": […]}`
response shapes, treats an empty body as `.notFound`, and passes the service's
own error text through as `.service`.

## Subsystems

### Flight lifecycle and archival

`Flight` carries scheduled / estimated / actual times at both ends;
`bestDeparture` and `bestArrival` resolve actual → estimated → scheduled.
`effectivePhase` infers status from the clock so demo flights stay live.

**A flight archives itself 30 minutes after landing** — `Flight.archivesAt`,
`Flight.isArchived(at:)`. `FlightStore` publishes a `clock` on a 30-second
timer purely so this transition re-renders while the app sits open; the
sections (`todayFlights` / `upcomingFlights` / `pastFlights`) are all computed
against `clock`, not `.now`.

The dividing line is **landing, not the calendar day**. Don't reintroduce
`isDateInToday` on the past/active split — that made a red-eye disappear at
midnight while still airborne.

### Stages, milestones and alerts

`Flight.stage(at:)` returns a `FlightStage` — thirteen cases from
`.checkInOpen` through `.gateClosing`, `.taxiingOut`, `.landingSoon` to
`.arrived`. It's derived from the clock, so the UI advances on its own and is
correct in Demo Mode. **`effectivePhase` is collapsed out of `stage()`**, so the
coarse phase and the fine stage can never disagree; don't reimplement either
one separately.

Only `.cancelled` and `.diverted` short-circuit on the stored phase. A stored
`.landed`/`.arrived` deliberately falls through to the clock — otherwise a
flight a provider marked "arrived" would sit on "Taxiing to gate" forever.

`Flight.milestones` is the single source of dated points (check-in, boarding,
gate close, departure, landing, bags). The timeline on screen, the countdown in
`FlightStageBar` and the notification scheduler all read it, so a boarding time
shown on the flight page is by construction the instant that fires the boarding
alert. Boarding and gate-close are **derived** (35/50 min and 15/20 min leads,
domestic/international) and are rendered with a `~` prefix.

`NotificationService` schedules local notifications — no server, no push
certificate, and they fire with the app closed. Two rules that matter:

- **`sync` clears and rebuilds everything** prefixed `flightdeck.`, so it's
  idempotent and safe to call often. It's called from `FlightStore.save()`,
  which every mutation already goes through — that's why nothing has to
  remember to reschedule.
- **iOS caps pending local notifications at 64.** `maxPending` is 56, sorted
  nearest-first, so what gets dropped is always the furthest away.

Change alerts (`FlightChange.between`) are a pure diff between two `Flight`
snapshots, fired from `FlightStore.refreshActive`. They can only be noticed
while the app is awake — there is no background refresh — and Settings says so
in plain words. Don't let the UI imply otherwise.

### Passport

`PassportStats.build(from:scope:now:)` is a **pure function over the whole
flight log**. There is no second copy of the data: delete a flight and every
stat moves with it. Scope is `.allTime` or `.year(Int)`; `availableYears` is
populated regardless of scope so the picker comes free.

Counted flights are those where `Flight.hasFlown(at:)` is true. Cancellations
are tracked separately — they're a delay statistic, not a trip, and are
excluded from distance, hours and on-time rate.

**Delay threshold is 15 minutes of arrival delay** (`Flight.delayThresholdMinutes`),
matching the US DOT definition so the numbers line up with published airline
statistics. Note `Flight.isDelayed` (10 min) still exists for the *live* status
pill — that's a UI nicety, not a statistic. Don't unify them without deciding
which meaning you want.

Distance comes from the bundled `airports.json` (~90 airports). Flights whose
endpoints aren't in it contribute no mileage, and the Passport says so via
`unresolvedAirports` rather than silently undercounting.

### Live tracking

Tracking is **flight-first**. Tapping a flight → `FlightDetailView` → tapping
the map header → `FlightTrackingMapView`: your aircraft on its route, no zoom
ceiling, every ADS-B contact around it (airborne *and* ground). Scopes
(Ground / Nearby / Route) set radius, poll interval and map style.

`AirportTrafficView` still exists for the different question "what's happening
at this field right now". Don't merge them.

Two lifetime rules that are easy to break:

- **`FlightMapView` must not stop the tracker in `onDisappear`.** Pushing the
  tracking map makes it disappear, and stopping there kills the live track at
  the exact moment the user asked to watch it. The tracker is a
  `@StateObject` on `FlightDetailView`; its `deinit` cancels the poll when the
  page is popped, which is the lifetime we want.
- **Everything that moves is drawn in one `Canvas` on a `TimelineView`
  display clock**, not as per-aircraft MapKit annotations. Thirty annotations
  updating every frame thrashes; one overlay doesn't. Positions come from
  `Track.state(at:)`, which dead-reckons between samples and eases onto each
  new fix — see `DeadReckoning` and `docs/live-traffic-plan.md`.

Because the traffic canvas sets `allowsHitTesting(false)` so gestures reach the
map, tap-to-identify is done manually: `MapReader` → `proxy.convert` → nearest
track within 28 pt. Both maps do this identically.

**Labels are earned by a tap, never drawn by default.** Printing a callsign
over every contact turned a busy field into a wall of text, and a callsign on
its own doesn't answer the question people have — which is where that aircraft
is *going*. A tap resolves the callsign through `FlightRouteService` (adsbdb,
keyless, global) and shows `BAW53M / LHR → NAS`. Route lookups are fired on
selection only; prefetching everything in view would be dozens of requests a
minute against a free community service. `RouteLookup` is the `@MainActor`
cache the `Canvas` reads synchronously — it cannot `await` mid-frame.

That route table is a *schedule*, not an observation: it says what that flight
number usually flies. It's labelled as a lookup everywhere it appears, and a
miss renders as "Route unknown", not as an error.

Camera follow preserves the user's pinch distance (`cameraDistance`, updated
from `onMapCameraChange`), and a `simultaneousGesture(DragGesture())` turns
follow off as soon as the user pans.

### Arrival forecast

`DelayHistoryStore` keeps a rolling punctuality record (60-day analysis window,
120-day retention — both constants live on `DelayObservation`, deliberately
*not* on the `@MainActor` store, so the non-isolated forecaster can read them).
It de-duplicates by leg-and-day, and a first-hand `.flown` record always beats
a `.provider` or `.simulated` one.

It's fed from two places:
- `FlightStore.recordCompletedFlights()` on every clock tick — idempotent.
- `DelayHistoryBackfill`, run when a flight page opens and the route hasn't
  been scanned in 12 hours. Real provider history with a key (sequential, ~15
  sampled dates, deliberately not concurrent — free tiers rate-limit hard);
  deterministic seeded synthetic history in Demo Mode.

`ArrivalForecaster.forecast(for:history:context:)` returns `nil` once the
flight is down or cancelled. The model, in order:

1. Hierarchical shrinkage from a 21% baseline through five progressively
   narrower tiers of history, each shrunk toward the tier below it.
2. Log-odds adjustments for live conditions (late inbound aircraft, FAA
   programs, IFR weather), split origin-side vs destination-side.
3. Once airborne, origin-side evidence is dropped — it's already in the live
   estimate — and the band narrows with flight progress.

**Synthetic history must stay visibly labelled.** `DelayObservation.Source`
carries `.simulated`, `ArrivalForecast.usesSimulatedHistory` propagates it, and
the card renders a Demo Mode warning. Don't let generated data pass as real.

## Conventions

- **Times render in the airport's local timezone**, never the phone's — use
  `Fmt.time(_:airportIATA:)`. `Flight.originCalendar` gives a calendar in the
  departure airport's zone for date bucketing.
- **Lenient decoding everywhere.** One malformed record must never blank a
  screen — see `Lenient<T>` and `AdsbResponse`.
- **Say when data is missing or estimated.** Empty ADS-B means "no receiver
  sees anything here", not "no aircraft"; positions on maps are extrapolations
  and are badged as such. This is a load-bearing product principle, not a
  nicety.
- Comments explain *why*, especially where a simpler-looking approach was
  tried and failed. Match that density.
- Persistence is JSON in Application Support (`flights.json`,
  `delay-history.json`). The AeroDataBox key is in UserDefaults — a documented
  trade-off for a dependency-free personal app; Keychain would be correct for
  anything shipped.

## Known gaps

- **No Live Activities, widgets, Watch app or CarPlay.** All four need an app
  extension target, which is the one thing that would force editing
  `project.pbxproj`. Live Activities are the highest-value item left.
- **No push.** Local notifications cover every alert with a knowable time;
  change alerts need the app awake. "Faster than the airline" is out of reach
  without a server.
- No test target — the forecaster's math (`percentile`, `logit`, `normalCDF`,
  shrinkage) is the obvious first candidate, and `Flight.stage(at:)` /
  `FlightChange.between` are both pure and now equally worth covering.
- `airports.json` covers ~110 airports; anything else degrades gracefully but
  loses distance and timezone accuracy — manually added flights say so.
- No calendar / TripIt / email import. Calendar is the tractable one.
- Seat is user-entered; nothing supplies it automatically.
- `Flight.inbound` ("where's my plane") is only ever populated in Demo Mode —
  no provider we use returns the previous rotation.

`docs/flighty-research.md` §5 is the full feature-by-feature audit against
Flighty, and is the place to record anything else that turns out to be missing.
