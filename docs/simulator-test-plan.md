# iOS Simulator test plan

A script for a local Claude Code session (on a Mac with Xcode) to verify the
Passport, live-tracking and arrival-forecast work. Everything here is
executable — no step says "check it looks right" without saying what right is.

**Context you need before starting:** read
`.claude/skills/flightdeck/SKILL.md`. It explains the invariants several of
these tests exist to protect.

> The branch this work landed on is `claude/flighty-passport-tracking-iv0t8z`.
> None of it has ever been compiled — it was written in a Linux container with
> no Swift toolchain. **Assume the first build will fail and budget for it.**
> Phase 0 is the real gate; everything after it assumes a clean build.

---

## Facts

| Thing | Value |
|---|---|
| Project | `FlightDeck.xcodeproj` (no workspace, no packages) |
| Scheme | `FlightDeck` (not shared — Xcode autocreates it on first open) |
| Bundle ID | `com.personal.flightdeck` |
| Minimum iOS | 17.0 |
| Test target | none — this document is the test suite |
| Network | adsb.lol, aviationweather.gov, nasstatus.faa.gov must be reachable |

## Setup

```bash
cd /path/to/flighty-pro
git checkout claude/flighty-passport-tracking-iv0t8z

xcrun simctl list devices available | grep -i iphone
DEVICE="iPhone 16"        # or any available iOS 17+ device

xcodebuild -project FlightDeck.xcodeproj \
           -scheme FlightDeck \
           -destination "platform=iOS Simulator,name=$DEVICE" \
           -derivedDataPath build \
           build 2>&1 | tail -40
```

Install and launch:

```bash
xcrun simctl boot "$DEVICE" 2>/dev/null || true
open -a Simulator
APP=$(find build/Build/Products -name 'FlightDeck.app' -maxdepth 3 | head -1)
xcrun simctl install booted "$APP"
xcrun simctl launch booted com.personal.flightdeck
```

Handy throughout:

```bash
# Where the app's data lives (flights.json, delay-history.json)
CONTAINER=$(xcrun simctl get_app_container booted com.personal.flightdeck data)
ls "$CONTAINER/Library/Application Support/"

# Screenshot
xcrun simctl io booted screenshot /tmp/shot.png

# Wipe state and start clean
xcrun simctl terminate booted com.personal.flightdeck
rm -f "$CONTAINER/Library/Application Support/"*.json
xcrun simctl launch booted com.personal.flightdeck
```

---

## Phase 0 — Build (the actual gate)

**0.1 — It compiles.** Run the build above. Expect failures on the first
attempt; this code was written without a compiler. Fix and re-run until clean.

Likely failure areas, in rough order of probability:

- **SwiftUI type-checking timeouts** in the larger view bodies
  (`PassportView.heroCard`, `FlightTrackingMapView.body`,
  `ArrivalForecastCard.gauge`). Symptom: *"unable to type-check this expression
  in reasonable time"*. Fix by extracting subexpressions into `let`s or small
  `@ViewBuilder` funcs — never by simplifying the design away.
- **`onTapGesture` overload ambiguity** on the `Map` in
  `FlightTrackingMapView` — the CGPoint-taking variant is iOS 17+. The closure
  parameter is explicitly annotated `(point: CGPoint)` to disambiguate; if it
  still complains, the fallback is a `.gesture(SpatialTapGesture())`.
- **Concurrency warnings** around `DelayHistoryBackfill` capturing a
  `FlightDataProvider` existential. Warnings are acceptable; errors mean the
  project got switched to Swift 6 language mode.
- **`ViewBuilder` local `let`s** in `PassportView.body` and the `#Preview` in
  `RootTabView` — if the compiler objects, hoist them into computed properties.

**0.2 — No new warnings that matter.**

```bash
xcodebuild ... build 2>&1 | grep -E "warning:" | grep -v "^$" | sort -u
```

Unused-variable and deprecation warnings in files this branch touched should be
fixed. Pre-existing ones elsewhere can stay.

**0.3 — Previews render.** Open `RootTabView.swift` and `StatusPill.swift` in
Xcode, resume the canvas. `RootTabView`'s preview constructs all three stores;
if it crashes, an `@EnvironmentObject` is missing somewhere in the tree.

---

## Phase 1 — Passport (feature 1)

Launch clean (wipe state first). Demo Mode seeds four sample flights: one
airborne now, a JFK→LHR connection, one tomorrow, and one that landed
~26 hours ago.

**1.1 — Tab exists.** Five tabs: Flights, Passport, Airports, Connection,
Settings. Passport uses a closed-book icon.

**1.2 — Headline tiles.** Open Passport. With the seeded data exactly one
flight has flown (LAX→SFO), so expect:

- Flights: **1**
- Miles: **~338** (LAX→SFO great circle)
- Time in the air: **~1h 21m** (actuals, not schedule)
- Airports: **2**, footnote "1 country · 1 airline"

Confirm miles is not 0 — 0 means `routeDistanceMiles` isn't resolving airports.

**1.3 — Map.** A route line LAX→SFO with two dots. Pinch-zoom works. The
"Line weight = how often you fly it" caption is present.

**1.4 — Delay tracker.** The seeded LAX→SFO landed ~3 min early, so:
Delayed **0**, On time **100%**, Time lost **0m**, Cancelled **0**, and the
line "Not one delayed arrival on record."

Tap through to the Delay Tracker screen. Headline reads `0m` in green,
on-time rate 100%, both "Worst" lists show their empty messages, and the
"How This Is Counted" card mentions **15** minutes.

**1.5 — Most flown aircraft.** Shows "Embraer E175 — 1 flight · 100% of
everything you've flown". No second-place list (only one type).

**1.6 — Records.** Longest flight LAX→SFO. Shortest is suppressed (same
flight — verifies the `shortest.id != longest.id` guard). "Top seat" shows the
prompt to add one, not a blank row.

**1.7 — Seat round-trip.** Flights tab → Recently Flown → LAX→SFO → Aircraft
card → type `14A` into Seat → return. Passport → Records now shows
"Top seat 14A · 1×", and the past-flight row subtitle includes "Seat 14A".
Force-quit and relaunch: the seat survives.

**1.8 — Year scope.** With only one flown flight there's one year chip plus
"All Time". Selecting the year shows the same numbers; selecting a year with
no flights shows the empty state with a "Show all time" button.

**1.9 — Passport is derived, not stored.** Delete the LAX→SFO flight
(long-press → Remove). Passport immediately returns to the empty state. This
is the test that catches anyone caching stats.

**1.10 — Volume.** Optional but worth it. Stop the app, write ~40 synthetic
completed flights into `flights.json` across several years, airlines,
aircraft and delays, relaunch. Check: ranked lists paginate via "Show all",
the weekday histogram has a visible peak, the map draws heavier lines on
repeated routes, worst-delay picks the true maximum, and scrolling stays
smooth.

## Phase 2 — 30-minutes-after-landing archival (feature 1)

The behaviour under test: a flight leaves the live list 30 minutes after it
lands, on its own, without relaunching.

**2.1 — Seeded state.** Fresh launch: Flights tab shows Today (the airborne
SFO→JFK), Upcoming (JFK→LHR, ORD→AUS), and "Recently Flown" with LAX→SFO —
which landed 26 h ago and is therefore archived.

**2.2 — The transition, live.** This is the important one. Edit
`flights.json` so a flight landed **29 minutes ago**:

```bash
xcrun simctl terminate booted com.personal.flightdeck
CONTAINER=$(xcrun simctl get_app_container booted com.personal.flightdeck data)
python3 - "$CONTAINER/Library/Application Support/flights.json" <<'PY'
import json, sys, datetime
path = sys.argv[1]
flights = json.load(open(path))
now = datetime.datetime.now(datetime.timezone.utc)
landed = now - datetime.timedelta(minutes=29)
f = flights[0]
f["phase"] = "arrived"
f["scheduledArrival"] = landed.strftime("%Y-%m-%dT%H:%M:%SZ")
f["actualArrival"] = landed.strftime("%Y-%m-%dT%H:%M:%SZ")
dep = landed - datetime.timedelta(hours=2)
f["scheduledDeparture"] = dep.strftime("%Y-%m-%dT%H:%M:%SZ")
f["actualDeparture"] = dep.strftime("%Y-%m-%dT%H:%M:%SZ")
json.dump(flights, open(path, "w"), indent=2)
print("landed at", landed, "- archives at", landed + datetime.timedelta(minutes=30))
PY
xcrun simctl launch booted com.personal.flightdeck
```

Now: the flight is in **Today**, not Recently Flown. Leave the Flights tab
open, on screen, and wait. Within ~30 seconds of the 30-minute mark it must
move to Recently Flown **without any interaction** — no tab switch, no pull to
refresh, no relaunch. `FlightStore`'s 30-second clock timer is what makes this
work; if it only moves after you touch something, the timer or the
`clock`-based sectioning is broken.

**2.3 — Boundary.** Repeat with 31 minutes: archived immediately at launch.

**2.4 — Midnight is not the rule.** Set a flight that departed 23:00 local
and lands 06:00 tomorrow, currently mid-flight. It must stay in Today while
airborne even though its departure date is "yesterday". This is the red-eye
regression.

**2.5 — Cancelled flights.** Set `"phase": "cancelled"` with a scheduled
arrival 40 minutes ago → archived. Confirm it appears in Past Flights with a
red "Cancelled" pill, and in the Passport counts as a cancellation but **not**
as a flown flight (flight count and miles unchanged).

**2.6 — Past Flights screen.** Passport → Past Flights. Month-grouped with
sticky headers, newest first. Search by IATA, airline name, flight number and
tail number each filter correctly; a nonsense query shows the "Nothing
matches" line.

## Phase 3 — Flight-centric live tracking (feature 2)

Demo flights have no real airframe, so the ADS-B lock in 3.4 needs a real
flight (see 3.7). Everything else works in Demo Mode.

**3.1 — Entry point is the flight.** Flights tab → tap the airborne SFO→JFK.
The map header carries a blue "Track this flight ›" pill. Tap **anywhere on
the header** — the whole thing is one target — and the full-screen tracking
map opens. Verify you never had to visit an airport page to get here.

**3.2 — Route and own aircraft.** The great-circle SFO→JFK line is drawn
dashed, both airports are dotted, and a white aircraft glyph sits along it
pointing toward JFK. The bottom card reads "DL 482 · SFO → JFK" with an
"Estimated" pill (orange) since demo flights aren't on ADS-B.

**3.3 — Unlimited zoom.** Pinch in as far as the simulator allows —
individual buildings should resolve, with no zoom clamp and no snap-back. Then
the `+`/`−` buttons: each halves/doubles the camera distance and animates.
This is the explicit ask; a zoom ceiling is a failure.

**3.4 — Traffic, ground and air.** The status capsule at the top reads
"*N* airborne · *M* on ground". Both numbers must be able to be non-zero —
that's the "airplanes around me both when I'm on the ground and in the air"
requirement. If you see only airborne contacts, check the Ground scope over a
busy field (3.6).

**3.5 — Tap to identify.** Tap any aircraft glyph. A card appears naming it
with type, altitude or Parked/Taxiing, speed and distance. Tapping it again,
or the ✕, dismisses it. Tapping empty map clears the selection. The selection
ring must **not** appear around your own aircraft when nothing is selected.

**3.6 — Scopes.** Switch Ground / Nearby / Route:

- **Ground** — satellite imagery, tight zoom, 3-second polls. Over a busy
  airport you should be able to read the taxi queue.
- **Nearby** — standard map, ~90 km across, 5-second polls.
- **Route** — frames the whole route; the follow button turns off by itself.

**3.7 — Real ADS-B (needs a key).** Settings → turn Demo Mode off, paste an
AeroDataBox key. Add a flight that's airborne right now. On its tracking map
the pill turns green "Live ADS-B", an accuracy ring appears around your
aircraft, and the glyph moves smoothly and continuously — **not** in 5-second
jumps. Jumping means the dead-reckoning path regressed.

**3.8 — Follow mode.** With follow on (filled location icon), the camera
recentres as the aircraft moves, **keeping your zoom level**. Drag the map:
follow switches off within one drag. Tap the button: it recentres and
re-engages.

**3.9 — Tracker lifetime (regression).** With a real tracked flight showing
"Live ADS-B", open the tracking map, wait 15 seconds, go back to the flight
page. The header must still show a live position — it must not fall back to
"Estimated" or "Searching". This is the `onDisappear` bug the branch fixed;
it's easy to reintroduce.

**3.10 — Background behaviour.** On the tracking map, press Home. Reopen
within a minute: polling resumes and the aircraft count refreshes. Nothing
should poll while backgrounded.

**3.11 — Airport traffic still works.** Airports → any airport → "Airport-Wide
Traffic". It should still open and still work, and its copy should point you at
the Flights tab for your own aircraft.

## Phase 4 — Arrival forecast (feature 4)

**4.1 — Card appears.** Open the upcoming ORD→AUS flight. Below the status
banner: an "Arrival Forecast" card with a large percentage, a risk phrase, a
scheduled/forecast/late-by row, an arrival window, and a confidence pill.

First open may briefly show "Building arrival forecast from the last 60
days…" while the backfill runs.

**4.2 — Demo history is labelled as generated.** In Demo Mode the card must
carry the purple "Demo Mode: this forecast is built from generated history"
warning. **If that warning is missing, stop and fix it** — unlabelled
synthetic data presented as a real forecast is the worst possible failure here.

**4.3 — It's stable.** Note the percentage. Leave the flight page, come back,
force-quit, relaunch. The number must be identical — synthetic history is
seeded from the route, and a forecast that reshuffles every visit is noise.

**4.4 — Evidence is inspectable.** Tap "What's driving this". Factors list
with per-factor minute contributions. At minimum a "N similar flights, last 60
days" row. The basis line under the window names the sample in plain English.

**4.5 — Sample size drives confidence.** Settings → Clear Punctuality History.
Return to a flight page *and pull to refresh* (the 12-hour backfill guard means
you may need to relaunch to force a rescan). With no history the card should
show "No history yet", a basis line about the industry baseline, and roughly
the 21% baseline probability.

**4.6 — Live signals move it.** Find a flight into a US airport currently
under an FAA program (check the Airports tab for a red/orange status, e.g. a
ground stop). Its forecast should include a factor row naming that program
with a positive minute contribution, and a visibly higher percentage than a
comparable unaffected flight.

**4.7 — In-flight mode.** Open the airborne SFO→JFK. The forecast's first
factor should be "Running N min behind" or "Tracking to schedule" with a
progress percentage, and the arrival window should be **narrower** than the
pre-departure ORD→AUS window — uncertainty collapses as the flight completes.

**4.8 — Landed flights have no forecast.** The completed LAX→SFO must show
no forecast card at all.

**4.9 — Delay history feeds itself.** Settings → "Observations stored" is
non-zero after visiting a flight page. Take a flight from live to landed (edit
`flights.json` per 2.2) and confirm the count includes it — flights you take
are folded in automatically.

**4.10 — Rate limiting (key mode only).** With a real key, open a flight for a
route never scanned before and watch Console for HTTP 429s. The backfill is
sequential with a 350 ms pause by design; a burst of 429s means someone made
it concurrent.

## Phase 5 — Regressions

**5.1** Airports tab: search, favourite, detail with FAA status and METAR.
**5.2** Connection tab: the seeded SFO→JFK / JFK→LHR pair is detected with a
risk rating and countdown.
**5.3** Add Flight: search `DL 100` in Demo Mode returns a result and adds it.
**5.4** Pull to refresh on Flights and on a flight page.
**5.5** Settings → Remove All Flights: confirmation warns the Passport goes
too; afterwards both Flights and Passport show empty states.
**5.6** Rotate to landscape on the tracking map and the Passport — no clipped
or overlapping chrome.
**5.7** Dynamic Type at XXL on Passport tiles and the forecast card — numbers
scale down rather than truncating.
**5.8** Airplane mode: no crashes, no spinners that never resolve. Traffic
shows a failure or no-coverage state; the Passport is entirely offline and
must be fully functional.

## Reporting back

For each phase: pass/fail, the diff of any fix applied, and screenshots for
1.2, 2.2 (before and after the transition), 3.3, 3.5 and 4.1. Call out
anything in Phase 0 that needed a real design change rather than a mechanical
fix — that's the signal about what was written blind and got it wrong.
