# What Flighty actually does — research notes

Background for the Passport, tracking and arrival-forecast work. Gathered from
Flighty's own marketing and help pages (via search summaries — `flighty.com` is
unreachable from this build environment's egress proxy, so the primary pages
were read through search result summaries rather than fetched directly),
plus third-party reviews and press coverage. Treat exact stat wording as
approximate; the *shape* of the features is well corroborated across sources.

---

## 1. Passport

Flighty's Passport is a lifetime travel record with a per-year "year in review"
mode. Corroborated stats across sources:

| Stat | Have it? | Notes |
|---|---|---|
| Total flights | ✅ | |
| Total distance flown | ✅ | Flighty frames it as miles; we add "× around the world" |
| Total time in the air | ✅ | |
| Airports visited (count + map) | ✅ | |
| Countries visited | ✅ | Derived from the bundled airport DB |
| Airlines flown | ✅ | |
| Most-flown aircraft type | ✅ | Explicitly called out in Flighty's own copy |
| Most-flown individual airframe | ✅ | Flighty tracks tail numbers; we tally by registration |
| Oldest / newest aircraft flown | ❌ | Needs an airframe age database we don't bundle |
| Top seat | ✅ | User-entered — no API supplies it |
| Most-flown routes | ✅ | Direction-agnostic city pairs |
| Total hours delayed | ✅ | The delay tracker headline |
| Worst delay | ✅ | |
| Worst airline for delays | ✅ | Plus worst arrival airports, which Flighty doesn't surface |
| Domestic / international / long-haul counts | ✅ | |
| Longest and shortest flight | ✅ | |
| Day of week most flown | ✅ | |
| Route map as a heat map (thicker = more frequent) | ✅ | Line weight scales with frequency |
| Shareable stat cards | ❌ | Deliberately skipped — see "Not built" below |
| "Get Me Off This Plane" (scheduled arrival → actual disembark) | ❌ | Needs gate-in and door-open times; our providers give runway times |

Flighty publishes an aggregate year-in-review too (in 2025: 22M flights,
34B miles, 78M hours across its user base). That's a server-side product, not
an app feature, and is out of scope for a personal app.

## 2. Delay prediction

How Flighty describes it:

- **Machine learning** over aviation-authority data plus incoming-aircraft
  information. Sources named across coverage: ADS-B tracking, FAA ground delay
  programs, historical route performance, and weather.
- **The physical aircraft is the key signal.** Flighty tracks the airframe
  assigned to your flight and can flag a delay while it's still inbound from
  its previous city — claimed at up to 6 hours before the airline acknowledges
  it, and up to 25 hours of forward visibility on where your plane is.
- **Covers two of every three US delays**: late-arriving aircraft (#1 cause)
  and ATC/airspace mandates (#2), plus weather and ground stops.
- **Predicted times shown alongside official ones**, never replacing them.
- Claims **>95% accuracy**, and notifications carry the reason —
  e.g. "Delayed 45m. Due to late arriving aircraft from New York."

What we built instead, and why it's honest about the difference:

Flighty trains on a fleet-wide dataset we don't have. A personal app sees only
the user's own flights, which for a specific route is a handful of samples a
year — nowhere near enough to state a percentage. So `ArrivalForecaster`:

1. Starts from the published US baseline (~21% of arrivals 15+ min late).
2. Refines it through progressively narrower slices of a rolling 60-day
   history — origin airport → that airline at that airport → the route → that
   airline on that route → that airline, route and time of day — each tier
   shrunk toward the one below it in proportion to how little data it has.
   Six flights on your exact route move the number without overriding it.
3. Adjusts in log-odds for the same live signals Flighty names: late inbound
   aircraft, FAA ground stops / ground delay programs / arrival delays, and
   IFR-or-worse weather at either end.
4. Once airborne, stops guessing: the live estimate becomes the centre and the
   band narrows with flight progress.

The card always shows its sample size, its basis in plain English, and every
factor that moved the number — a bare percentage from a personal-scale dataset
would be unfalsifiable, which is worse than no percentage.

**Where the history comes from** is the honest weak point and is surfaced in
the UI: with an AeroDataBox key we backfill the same flight number across ~15
sampled past dates; in Demo Mode we generate deterministic synthetic history,
labelled as generated wherever it appears. Neither is a fleet-wide dataset.

## 3. Live map and tracking

- Tapping a flight opens flight details with a live map; the aircraft moves in
  real time along its route.
- Interactive detail: tapping a gate badge zooms the map to that gate.
- Flighty's tracking is oriented around *your flight*, not around airports —
  which is what prompted the rework here. Aircraft tracking used to require
  going through an airport page; it now hangs off the flight, with the airport
  view kept for the separate "what's happening at this field" question.

## 4. Notifications and flight stages

Flighty's own help page lists these alerts: delay prediction, connection
assistant, friends' flights, aircraft type & tail assignments, flight plan
filed, airport delay, inbound plane, gate change, taxi/takeoff/landing times,
cancellation or diversion, baggage claim, and check-in reminder. Reviews add a
day-before "flight plan filed" note, a two-hour warning with terminal and gate,
and a one-hour-to-landing alert.

The earlier note in this file said notifications needed a paid developer
account and a server. That conflated two different things, and the distinction
turns out to matter a lot:

- **Push** notifications need a server and a certificate. Flighty's core claim —
  alerts *faster than the airline* — is entirely on that side of the line, and
  is not reachable here at any effort.
- **Local** notifications need neither. Anything with a knowable date can be
  handed to iOS in advance and it fires with the app closed.

Almost every alert on Flighty's list has a knowable date, so they are now
scheduled locally: check-in, boarding, gate close, departure, one hour to
landing, touchdown, and bags. See `NotificationService`.

What genuinely can't work without a server is the *change* half — a gate move,
a fresh delay, a cancellation. Those are only discovered when the app is awake
and refreshing, so they fire then and Settings says so in plain words rather
than letting anyone assume their pocket will buzz. `FlightChange` holds the
diff rules.

Alongside that, `FlightStage` gives the lifecycle the granularity Flighty
shows. It's derived from the clock, not from a provider, so the screen walks
itself through Check-in open → Boarding soon → Boarding → Gate closing →
Taxiing → In the air → Landing soon → Taxiing to gate → At the gate → Arrived,
and stays correct in Demo Mode. `FlightPhase` is still what gets persisted;
`effectivePhase` is collapsed out of the stage so the two can't drift.

Boarding and gate-close times are **derived, not published** — no feed we can
read carries them. 35 minutes before departure domestic, 50 international, and
gate close 15/20. They lean early on purpose: being early to a gate costs
nothing. Every derived time on the timeline is prefixed `~`.

## 5. Full feature audit

Everything advertised on Flighty's App Store listing and help pages, against
what this app does. Social features (Flighty Friends, sharing) are excluded by
choice — this is a personal-use app with no social surface.

### Tracking and live data

| Flighty | Here | Notes |
|---|---|---|
| Live tracking on pilot-grade FAA / Eurocontrol data | ⚠️ | ADS-B via adsb.lol. Positions are as good; we have no ATC feed, so no flight plans or clearance data |
| Ground radar while taxiing | ✅ | Ground scope, satellite imagery, surface positions with `true_heading` |
| Proximity radar — nearby aircraft | ✅ | Nearby / Route scopes on the flight tracking map |
| Tap an aircraft to identify it | ✅ | Callsign + route via adsbdb; labels only appear on tap |
| Actual filed flight plan, live-streamed | ❌ | No keyless source |
| 25-hour "where's my plane" inbound tracking | ⚠️ | The card exists; only Demo Mode supplies inbound legs — no provider we use returns the previous rotation |
| Gate predictions | ❌ | No source |
| Delay prediction with a stated reason | ✅ | `ArrivalForecaster` — different method, see §2, and it shows its working |
| Aircraft model and tail number | ✅ | From AeroDataBox |
| Aircraft age / name / photo | ❌ | Needs an airframe database we don't bundle |

### Alerts

| Flighty | Here | Notes |
|---|---|---|
| Check-in reminder | ✅ | Scheduled locally, 24 h out |
| Boarding | ✅ | Scheduled; time is derived, see §4 |
| Gate close / final call | ✅ | Scheduled |
| Departure | ✅ | Scheduled |
| One hour to landing | ✅ | Scheduled |
| Landing | ✅ | Scheduled |
| Baggage claim | ✅ | Scheduled, plus an immediate alert when a belt is assigned |
| Gate change | ⚠️ | Fires, but only when the app refreshes |
| Delay / cancellation / diversion | ⚠️ | Same |
| Aircraft or tail reassignment | ⚠️ | Same |
| Inbound aircraft running late | ⚠️ | Same, and limited by the inbound gap above |
| *Faster than the airline* | ❌ | Structurally impossible without a push server. This is Flighty's headline feature and the honest answer is that we don't have it |
| Airport weather / ground-stop alerts | ⚠️ | Shown on the flight page; not pushed |
| Tight-connection warning | ⚠️ | Connection tab; not pushed |
| Taxi and takeoff *times* recorded | ❌ | Would need position tracking to continue in the background |

### Assistants and import

| Flighty | Here | Notes |
|---|---|---|
| Connection assistant | ✅ | Connection tab, with the gap rules in `ConnectionRules` |
| Morning-of assistant | ❌ | Would be a cheap addition — it's another scheduled local notification |
| Check-in assistant with booking reference and link | ⚠️ | We remind; we hold no reservation data |
| Calendar / TripIt / email import | ❌ | The largest remaining convenience gap. Calendar is the tractable one |
| Bulk import from other trackers | ❌ | |
| Manual entry for any flight, any date | ✅ | Better than parity: prefilled from a keyless route lookup, so it works for flights beyond any live feed |

### Passport

Covered in §1. Still missing: airframe age, shareable stat cards (deliberate),
flight notes and travel-reason tagging, and data export.

### Airport intelligence

| Flighty | Here | Notes |
|---|---|---|
| Live airport delay status | ✅ | FAA NAS Status, US only |
| Plain-language "why" from METAR/TAF | ⚠️ | METAR shown and used by the forecaster; not narrated |
| Global airport status map | ❌ | |
| Departure/arrival performance by hour | ❌ | |
| Most-visited airports | ✅ | Passport |
| Favourite airports with disruption alerts | ⚠️ | Favourites exist; no alerting on them |
| Airport delay *forecasting* — when delays will end | ❌ | We show current programs, not their end |
| Terminal and amenity maps | ❌ | |

### Platform surfaces

All of these need a widget or app extension target, which means editing
`project.pbxproj` — the one thing this project's layout otherwise never
requires. They're grouped here because they're one decision, not eight:

| Flighty | Here |
|---|---|
| Live Activities / Dynamic Island | ❌ |
| Lock-screen and home-screen widgets | ❌ |
| Apple Watch app and complications | ❌ |
| CarPlay | ❌ |
| App Intents, Siri Shortcuts, Spotlight | ❌ |
| iCloud sync across devices | ❌ — persistence is a local JSON file |
| iPad / Mac | ⚠️ — builds and runs; laid out for iPhone |

Live Activities are the highest-value item on that list by a distance: a flight
tracker's natural home is the lock screen. Worth noting that a Live Activity
started while the app is open can be *updated locally* from the app — the push
server is only needed to update it while the app is closed. So a partial
version is reachable; a full one isn't.

## Sources

- [Flighty on the App Store](https://apps.apple.com/us/app/flighty-live-flight-tracker/id1358823008) — the fullest feature list, and the basis of §5
- [How do I manage flight tracking notifications in Flighty?](https://flighty.com/help/flighty-notifications)
- [Flighty Passport help page](https://flighty.com/help/passport)
- [Flighty Passport product page](https://flighty.com/passport)
- [How Flighty predicts flight delays](https://flighty.com/help/delay-predictions)
- [The Points Guy — everything you need to know about Flighty](https://thepointsguy.com/travel-gear/everything-you-need-to-know-about-flighty-app/)
- [Going.com — Flighty app review](https://www.going.com/guides/flighty-review)
- [Thrifty Traveler — why Flighty is a must-have](https://thriftytraveler.com/reviews/flighty-pro-app/)
- [TechCrunch — Flighty can now predict delays using machine learning](https://techcrunch.com/2024/08/06/flightys-popular-flight-tracking-app-can-now-predict-delays-using-machine-learning/)
- [Techlicious — Flighty predicts when airport delays will end](https://www.techlicious.com/blog/flighty-flight-tracking-app-airport-delay-predictions/)
- [World Airline News — Flighty's first year-in-review global Passport report](https://worldairlinenews.com/2025/12/11/flighty-launches-its-first-year-in-review-global-passport-report-including-the-most-delayed-airlines-in-2025/)
- [9to5Mac — Flighty year-in-review features](https://9to5mac.com/2023/12/12/flighty-year-in-review-features/)
- [MacSources — Flighty app review](https://macsources.com/flighty-app-review/)

FlightDeck is an independent personal-use app. It is not affiliated with
Flighty LLC, and ships no Flighty artwork, code, or trademarked assets.
