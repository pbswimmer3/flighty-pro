# FlightDeck store review: listing strategy, copy spec, card spec

> **Update 2026-11-11:** the owner chose the name **Flight Dash** (store name "Flight Dash: Flight Tracker"). Section 2 below is the original analysis.

_Written 2026-11-11 on branch `claude/app-store-prep` by the lead reviewer. Everything below was checked against the code in this worktree (airport counts, data hosts, feature list) and against the `raw-before` captures in `docs/store/raw-before/`. Two agents execute from this file alone: **opus** writes the copy files, **sonnet** writes the scripts and renders the cards. Neither edits this file; both read all of it. File ownership is in section 5 and is disjoint._

Reference for rigour and file layout only (not wording, not visual style): `C:\Users\pradb\AI-Scripts\ride-compare\docs\store\` and `C:\Users\pradb\AI-Scripts\ride-compare\tools\check-listing.mjs`, `make-store-screenshots.mjs`.

---

## 1. Verdict and positioning

**Verdict: ready to list once the UI packages (P0–P4 in `docs/ui-review.md`) are merged and the screenshots are retaken — with one decision that blocks everything: the name.** "FlightDeck - Flight Tracker" already exists on the App Store (see section 2). Everything else is in good shape: no accounts, no backend, honest labelling, a real Demo Mode a reviewer can use, and a privacy story that is genuinely "nothing collected".

**Who it is for.** One person who flies often enough to care, is slightly nerdy about it, and wants one screen per flight that tells the truth: where the plane is, when it will really land, whether the connection holds, and a lifetime record that builds itself. Not for pilots, not for spotters, not for families tracking each other.

**The one-line promise.** _Your flight, live, with a forecast that shows its working and a Passport that writes itself._

**Three differentiators that are true in the code** (every claim here has a file behind it; copy may cite them freely):

| # | Claim | Where it is true |
|---|---|---|
| 1 | **An arrival forecast with its reasons.** Chance of a 15-minute-late arrival, a predicted time and a 20th–80th percentile window, built from a rolling 60-day punctuality record plus live conditions (late inbound aircraft, FAA programs, IFR weather). The card names its sample size and lists every factor that moved the number. | `Services/ArrivalForecaster.swift`, `Stores/DelayHistoryStore.swift`, `Views/Flights/ArrivalForecastCard.swift` |
| 2 | **Live tracking that shows who is around you, on the ground too.** Your aircraft on its great-circle route with every ADS-B contact around it; three scopes: Ground (5 nm, satellite, the taxi queue), Nearby (40 nm), Route. Tap any aircraft to see who it is and where it is going. Motion is dead-reckoned between fixes and labelled as an estimate. | `Views/Flights/FlightTrackingMapView.swift`, `Stores/TrafficStore.swift`, `Utilities/DeadReckoning.swift` |
| 3 | **A Passport computed from your flights, not a second database.** Flights, miles, hours, airports, countries, airlines; a route map weighted by frequency; a delay tracker at the US DOT 15-minute threshold (hours lost, on-time rate, worst airlines and airports); records; searchable past flights. Delete a flight and every number moves. | `Models/PassportStats.swift`, `Views/Passport/*` |

Frame around all three: **free, no account, no subscription, no server; works out of the box in Demo Mode; real flight lookups need the user's own free AeroDataBox key.** Say this early and plainly. It is a strength for a personal app and it is what a reviewer needs to hear.

**What must never be claimed** (not in the app): Live Activities / Dynamic Island, widgets, Apple Watch, push notifications, "faster than the airline", background refresh, calendar or email import, iPad layouts (see section 6), ML/AI predictions (the forecast is a statistical model, call it that). Delay and gate-change alerts fire **only while the app is open**; boarding/gate-close/departure/landing/bags alerts are scheduled locally and do fire with the app closed.

---

## 2. Name and subtitle

### The problem

A web search on 2026-11-11 found **"FlightDeck - Flight Tracker"** (App Store id 6759628645, developer JAC LLC, iOS 17+, free with subscription, ~180 US ratings) — a consumer flight tracker in the same category with the same brand word. Also on the store: "FlightDeck EFB" (id 1592153352), "Flight Deck ONE", "Flight Deck FMS", "De Havilland Flight Deck". This is almost certainly why the App Store Connect record had to be created as **"Prad's Flight Deck"**: the plain name was already taken.

Consequences:

- App Store Connect enforces exact-name uniqueness, so some "FlightDeck: …" variant may save. But a second flight tracker called FlightDeck is a **Guideline 4.1 (copycat) and 5.2.1 (confusingly similar) risk**, and every search for the name lands on the other app.
- "Prad's Flight Deck" is fine for internal TestFlight. For a **public TestFlight link** the name is shown to every tester, and for the App Store it reads as a hobby project. Decide the name now; it is cheap to change before the first release and expensive after.

### Options, ranked

The web searches found no app with the names in options 1 and 2 (searched apps.apple.com for each on 2026-11-11). That is evidence, not proof: **the owner verifies by typing the name into App Store Connect, which rejects a taken name immediately**, and by a quick trademark search (USPTO TESS) for the brand word.

| Rank | Name (≤ 30) | Count | Notes |
|---|---|---|---|
| 1 | **Overwing: Flight Tracker** | 24 / 30 | "Overwing" is an aviation word (the overwing exit), short, pronounceable, no app found. Home-screen name "Overwing". Descriptor "Flight Tracker" is the category term people search. |
| 2 | **Holdshort: Flight Tracker** | 25 / 30 | "Hold short" is a taxiway instruction — avgeek-flavoured, no app found. Slightly more obscure than Overwing. |
| 3 | **FlightDeck: Flights & Passport** | 30 / 30 | Keeps the brand. Only if ASC accepts it **and** the owner accepts the 4.1 risk and the discoverability loss. Not recommended for the App Store; acceptable for TestFlight if the owner wants to defer the rename. |

Not recommended: "Tailfin" (an existing cycling-equipment brand), anything with "Radar" (reads as Flightradar24), anything with "Flighty", "Aware" or an airline name.

**If the owner renames**, the code changes are small but outside the store packages: `INFOPLIST_KEY_CFBundleDisplayName` in `FlightDeck.xcodeproj/project.pbxproj` (two configurations), `WelcomeView` title ("Welcome to FlightDeck"), the Settings About footer, `docs/privacy-policy.md` title and first line, the README title. The bundle id `com.personal.flightdeck`, the repo name, the notification prefix `flightdeck.` and the scheme can all stay — none is user-visible. The ASC record name is changed under App Information.

**Working assumption for the copy below: option 1, "Overwing".** Opus writes the listing with the brand word as a single token spelled exactly `Overwing` so the owner can replace it with one find-and-replace if they pick differently. The three name options are all written into `listing.md`; the subtitle and keywords are chosen for option 1 and `check_listing.py` checks keyword overlap against all three.

### Subtitle (≤ 30), ranked

| Rank | Subtitle | Count | Why |
|---|---|---|---|
| 1 | **Live map, delay odds, Passport** | 30 / 30 | The three differentiators in the order a buyer cares about them. "Passport" is the app's own noun and earns its capital. |
| 2 | **Track, forecast, remember** | 25 / 30 | Verb triad; reads well under the name; weaker for search. |
| 3 | **No account. No subscription.** | 28 / 30 | True and verifiable, and a real reason to install next to the paid trackers. Loses the feature pitch. |

Apple's subtitle rule: no references to other apps, no unverifiable claims. All three pass. **Do not** use "Flighty-style", "like …", "#1", "best", "fastest".

---

## 3. Copy spec (owner: **opus**)

### Tone

Plain, specific, second person, present tense. Short sentences. Numbers where they exist. No exclamation marks, no emoji, no "seamless", "powerful", "ultimate", "revolutionary", "AI-powered", "ML". Explain aviation words the first time (ADS-B: "the positions aircraft broadcast"; METAR: "the airport weather report"). Every feature sentence should survive the question "could a reviewer open the app and find this?" Honesty is a feature here: the app labels estimates and samples on screen, and the copy does the same.

**Words to use:** live, forecast, chance of delay, Passport, lifetime, on this device, no account, no subscription, Demo Mode, sample trip, your own key, in the airport's time zone, shows its working, estimated.

**Words and names to avoid everywhere in metadata:** Flighty, Flightradar24, FlightAware, App in the Air, TripIt, any airline name or code in name/subtitle/keywords/promo text (the description may say "Delta 482" only inside the sentence that explains the sample trip — prefer not to), "radar" as a noun for the app, "navigation", "ATC", "pilot", "cockpit" (the name "Overwing"/"FlightDeck" plus those words would imply a pilot tool), "secure"/"securely" for the API key (it is in app preferences, not the Keychain — say "stored on this device"), "real-time" (say "live"), "predict" as a verb for the app itself (say "forecast"), Apple/iPhone claims of endorsement.

### Facts to cite (verified in the repo on 2026-11-11)

| Fact | Value | Source |
|---|---|---|
| Curated airport database (Airports tab, terminals and minimum connection times) | **110 airports in 49 countries, 50 in the US**, bundled offline | `FlightDeck/Resources/airports.json` |
| World fallback airports (any IATA code resolves on maps and in the Passport) | **7,918 airports** from mwgg/Airports (MIT) | `FlightDeck/Resources/airports-world.json`, `scripts/build_world_airports.py` |
| Keyless data | FAA NAS Status (nasstatus.faa.gov) for US airport delay programs; NOAA Aviation Weather Center (aviationweather.gov) for METARs worldwide; adsb.lol for live aircraft positions; adsbdb.com for callsign → route | `Services/FAAStatusService.swift`, `WeatherService.swift`, `AdsbClient.swift`, `FlightRouteService.swift` |
| Keyed data | AeroDataBox via RapidAPI (`aerodatabox.p.rapidapi.com`), user's own free Basic-plan key; live status about a week ahead; flights further out are shown as "Projected" from this week's timetable and swapped for the real schedule automatically | `Services/AeroDataBoxProvider.swift` |
| Demo Mode | Default on. Sample trip built around the current time: one flight in the air (SFO → JFK), a connection later today (JFK → LHR), tomorrow's flight (ORD → AUS), one landed yesterday (LAX → SFO). Airport status, weather and live traffic are always real. Manual entry works without a key. | `Services/DemoFlightProvider.swift`, `Stores/SettingsStore.swift` |
| Forecast | 15-minute arrival-delay threshold (US DOT definition); 60-day window; baseline 21% then five tiers of history, each shrunk toward the one below; live adjustments for late inbound aircraft, FAA programs, IFR weather; 20th–80th percentile arrival window; card names sample size and factors; Demo Mode history is generated and labelled | `Services/ArrivalForecaster.swift`, `Models/DelayObservation.swift` |
| Flight stages | 13 stages from "Check-in open" to "Arrived", derived from the clock | `Models/FlightStage.swift` |
| Alerts | Local notifications for check-in, boarding, gate close, departure, landing, bags — fire with the app closed. Delay and gate-change alerts only while the app is open (no server). | `Services/NotificationService.swift`, `Models/FlightChange.swift` |
| Flights archive | 30 minutes after landing | `Models/Flight.swift` |
| Tracking scopes | Ground 5 nm (satellite), Nearby 40 nm, Route | `Views/Flights/FlightTrackingMapView.swift` |
| Connection ratings | Relaxed / Normal / Tight / Risky / Misconnect, from live estimated times, per-airport minimum connection time, +15 min for a terminal change | `Models/Connection.swift` |
| Passport | flights, miles ("× around the world"), hours, airports, countries, airlines; route map weighted by frequency; delay tracker; records; most-flown aircraft and tail; searchable past flights; per-year or all-time | `Models/PassportStats.swift` |
| Platform | iOS 17+, iPhone, dark interface, SwiftUI + MapKit, zero third-party dependencies, no server | `project.pbxproj` |
| Version | 1.0 (build 1 in the project; Codemagic increments the build number per upload) | `project.pbxproj`, `codemagic.yaml` |
| Bundle id / ASC | `com.personal.flightdeck`, app id 6828448145 | owner |
| Encryption | `ITSAppUsesNonExemptEncryption = NO` already set (HTTPS only) | `project.pbxproj` |

### `docs/store/listing.md` — structure

Mirror the ride-compare file's skeleton exactly, because `scripts/check_listing.py` parses it: a `<!-- limit: <field> <max> chars|bytes -->` line, a ```` ```text ```` block, a blank line, then `Count: **N / MAX characters**` (or bytes). Fields, in order: `name-1`, `name-2`, `name-3` (30 chars each), `subtitle` (30), `promotional-text` (170), `description` (4000), `keywords` (100 bytes), `whats-new` (4000), `review-notes` (4000 bytes), `beta-description` (4000), `what-to-test` (4000). Counts are written by `python scripts/check_listing.py --write`; never hand-edit a count. Open the file with a 5-line header (what it is, date, version, bundle id, how counts are checked) and a "Rules this listing follows" table citing Apple's pages (App information, Platform version information, Screenshot specifications, Age ratings, App Review Guidelines 2.1(a), 2.3, 2.3.1, 2.3.3, 2.3.7, 2.3.9, 4.1, 5.2.1, 5.2.4). Sections after the fields: Categories, Age rating questionnaire, Copyright, URLs (owner), Screenshots (the table from section 4 with filenames), App icon, Other ASC answers, TestFlight (beta review contact fields), Decisions made for the owner.

**Promotional text (≤ 170).** Benefit-led, no feature list, no name. Draft to tune (168 chars): _Your flight, live: a countdown to boarding, a forecast of when you'll really land, real aircraft around you on the map, and a Passport built from every flight you take._

**Description (≤ 4000, aim 2,400–3,000).** Structure:

1. **Two-sentence hook**: the promise, then the frame (free, no account, no subscription, nothing leaves your phone).
2. **YOUR FLIGHT, LIVE** — card with progress and status, times in the airport's time zone with the original struck through when things move, countdown to the next thing, the 13 stages, alerts (be exact about which fire with the app closed), flight page: route map, timeline with gates and bag claim, where your plane is coming from (note: inbound is only in Demo Mode today — say "when your data source provides it" or leave it out; prefer leave out), weather at both ends.
3. **A FORECAST THAT SHOWS ITS WORKING** — chance of delay, predicted arrival, likely window; what it is built from; "it names its sample size and every factor that moved the number".
4. **EVERY AIRCRAFT AROUND YOU** — the three scopes, tap to identify, ground scope and the taxi queue, "positions are estimates and are labelled as such", "coverage comes from a volunteer network, so it is good at big airports and can be empty elsewhere — the app says so rather than showing an empty sky".
5. **WILL YOU MAKE THE CONNECTION?** — auto-detected, five ratings, live times, minimum connection times, terminal change.
6. **A PASSPORT THAT WRITES ITSELF** — the stats; DOT 15-minute threshold; "computed from your flights, so delete one and every number follows".
7. **AIRPORTS** — 110 bundled airports with terminals and connection times; FAA ground stops and delay programs in plain English (US airports); decoded weather worldwide with the raw METAR; airport-wide live traffic on satellite imagery.
8. **HOW IT GETS ITS DATA** — the keyless sources by name; **Demo Mode** (what it is, that it is on by default, that samples are labelled, that status/weather/traffic are always real); **real flights need your own free AeroDataBox key from RapidAPI** (Settings → Live flight lookups), or add flights by hand; what the free plan reaches (about a week; further flights are shown as Projected and update themselves).
9. **PRIVATE BY DESIGN** — no account, no server, no analytics, no ads; flights and settings stay on this device; the key is stored on this device; requests go straight from the phone to the data services; alerts are local notifications.
10. **GOOD TO KNOW** — iPhone, iOS 17+; delay/gate-change alerts need the app open; FAA programs are US-only; ADS-B coverage varies.
11. **Required closing lines**, verbatim: _Positions shown on maps are estimates. Overwing is not an air-traffic-control tool and must never be used for navigation or separation._ and _Overwing is an independent app. It is not affiliated with, endorsed by or sponsored by any airline, airport or data provider. Airport status comes from the FAA, weather from NOAA, live aircraft positions from the adsb.lol community network, routes from adsbdb, and flight schedules from AeroDataBox when you add your own key._

`check_listing.py` fails if either closing line is missing (match on "not an air-traffic-control tool" and "not affiliated with").

**Keywords (≤ 100 bytes, comma-separated, no spaces).** Exclude every word already in any name option or the chosen subtitle (Apple indexes those): with option 1 + subtitle 1 that removes `overwing, flight, tracker, live, map, delay, odds, passport` (and `flights`, `flightdeck`, `holdshort`). Candidate list with rationale — pick to fill ≤ 100 bytes, singular forms, most-searched first:

| keyword | why |
|---|---|
| status | "flight status" is the top query in the category |
| delays | plural, since "delay" is in the subtitle (the checker treats `delay`/`delays` as the same word — if it does, drop it) |
| airport | airports tab, FAA status |
| gate | gate changes, gate alerts |
| boarding | boarding countdown and alert |
| layover | connection assistant |
| connection | same |
| adsb | avgeek query, true feature |
| metar | same |
| faa | ground stops |
| miles | Passport |
| avgeek | community term, no trademark |
| log, logbook | "flight log" searches (FlightLog apps exist; the generic word is fine) |
| plane, jet, aviation | generic fill if bytes remain |

Draft (96 bytes): `status,delays,airport,gate,boarding,layover,connection,adsb,metar,faa,miles,avgeek,log,plane,jet`. Never: `flighty`, `flightradar`, `flightaware`, `radar24`, airline names, `apple`, `free` (Apple ignores it), `app`.

**What's New (≤ 4000).** Not shown for a first App Store version; write a 2–3 sentence version anyway (ASC may ask, and it seeds 1.0.1).

**Review notes (≤ 4000 bytes)** — paste-ready, in this order, with `[OWNER: …]` placeholders only for name/email/phone:

- NO SIGN-IN IS NEEDED. The app has no account system.
- HOW TO SEE EVERYTHING (Demo Mode, on by default): the sample trip (which flight is in the air, which is a connection), the flight page (map header, tap "Track this flight" for the live map, the Arrival Forecast card and "What's driving this"), Connection tab, Passport tab and Delay Tracker, Airports → JFK (live FAA status, weather, Airport-Wide Traffic), Settings (alerts, Demo Mode, key field, privacy policy, acknowledgements). State that samples are labelled "Demo Mode"/"Sample" on screen, and that airport status, weather and aircraft positions are real even in Demo Mode.
- WHY THERE IS NO DEMO ACCOUNT: real flight lookups need the reviewer's own free AeroDataBox key (RapidAPI Basic plan); we ask that the built-in Demo Mode be accepted in lieu (Guideline 2.1(a)). Manual entry (Add Flight → Enter it yourself) works without a key.
- DATA: list the five hosts and what is sent (airport codes, callsigns, a map area, flight numbers + the user's own key). No server of ours; no analytics; nothing stored off-device. Notifications are local. No location permission.
- SAFETY: positions are estimates; not an ATC/navigation tool; the app says so in Settings → About and on the traffic screens.
- THIRD-PARTY CONTENT: airport data from mwgg/Airports under MIT, notice in Settings → Acknowledgements. Airline names appear as plain text and two-letter monograms (no logos).
- Contact line.

**TestFlight texts** (go in `listing.md` as fields and are repeated in `review-notes.md`):

- **Beta App Description (≤ 4000, aim ~900)**: what the app is (3 lines), what testers can do without a key (everything, in Demo Mode, samples labelled), how to add a real flight (manual entry; or a free AeroDataBox key — with the RapidAPI steps), what is not in the build (Live Activities, widgets, Watch, push), the safety line, and how feedback works (TestFlight screenshot → Send Beta Feedback; the feedback is read by an automated pipeline that files an issue and proposes a fix — say "your feedback goes to the developer's issue tracker" without naming tools).
- **What to Test (≤ 4000, aim ~700)**: a numbered walk: 1 Welcome sheet and the sample trip; 2 flight page, forecast, "Track this flight" with all three scopes (note that coverage varies); 3 turn on alerts in Settings and check a boarding alert arrives for the sample flight; 4 Connection tab; 5 Passport and Delay Tracker, switch year; 6 Airports → JFK, Airport-Wide Traffic; 7 add a flight by hand, delete it, confirm the Passport updates; 8 with a key: add a real flight by number, pull to refresh; 9 Dynamic Type at Larger Text and VoiceOver on the flights list. Ask testers to report anything that says "HTTP", any blank screen, any time shown in the wrong zone.
- **Feedback email**: `[OWNER]`. **Beta App Review contact**: first name, last name, phone, email `[OWNER]`. **Sign-in required**: No. **Privacy policy URL**: required for external testing, see section 6.

### `docs/store/app-privacy-answers.md`

Verified facts for the App Privacy questionnaire (the owner enters them in ASC → App Privacy):

- There is **no server, no analytics, no crash reporting, no ads SDK, no third-party SDK at all** (zero dependencies). The developer receives nothing.
- Network requests go from the phone to: nasstatus.faa.gov (no parameters beyond the feed), aviationweather.gov (airport code), api.adsb.lol (a callsign, or a lat/lon/radius of an **airport or the flight's own estimated position** — never the phone's location; the app has no location permission), api.adsbdb.com (callsign), Apple Maps tiles (MapKit, Apple's policy), and only with a user-entered key, aerodatabox.p.rapidapi.com (flight number, date, the user's own key).
- Stored on device only: `flights.json`, `delay-history.json` in Application Support; settings, favourites and the AeroDataBox key in UserDefaults. Deleted by Settings → Remove All Flights / Clear Punctuality History, or by deleting the app.
- Notifications: local, scheduled on the device; no push token exists.
- **Recommended answer: "Data Not Collected."** Reasoning to write out: Apple counts data as collected when it is transmitted off device in a way that lets the developer or partners access it beyond servicing the request; these are public data services the user's phone queries directly, the developer never sees the traffic, nothing is tied to an identity, and the only user-provided value sent (the AeroDataBox key) goes to the user's own account at that service. Contrast with ride-compare (which declared Location and Phone Number because of user accounts): nothing comparable exists here.
- **Tracking**: No. No ATT prompt.
- **Privacy manifest**: there is **no `PrivacyInfo.xcprivacy` in the project**, and the app uses UserDefaults, a required-reason API (category `NSPrivacyAccessedAPICategoryUserDefaults`, reason `CA92.1`). TestFlight uploads have gone through, but App Review can flag ITMS-91053. Record this as an open item for a code package (one plist file under `FlightDeck/`, with `NSPrivacyTracking` false, no collected data types, that one API reason). Opus documents it; it is not a store-package file.
- Privacy policy URL: `docs/privacy-policy.md` already exists (P4). The owner hosts it (section 6).

### `docs/store/review-notes.md`

The App Review notes and the TestFlight beta texts in paste order, each with a one-line "paste into ASC → … " pointer, plus: the Beta App Review contact block, Export compliance (already NO), Content rights ("does this app contain, show or access third-party content?" → Yes: public FAA/NOAA/ADS-B data and MIT-licensed airport data, with the attribution screen named), the demo walk-through in checklist form, and a "known limitations the reviewer may hit" list (empty ADS-B at quiet airports; FAA status is US-only; the sample trip's times move with the clock so the exact numbers in screenshots will differ).

### `docs/store/support.md`

Plain-English support page the owner hosts at the Support URL. Sections: contact (placeholder email + GitHub issues link); Getting started (Demo Mode, Welcome sheet, Add Flight by hand, the free key in 4 steps); Common questions — "Why do I see flights I didn't add?" (sample trip, how to remove, Load Sample Trip to bring it back), "How do I track a real flight?", "The app says No ADS-B coverage", "Alerts didn't arrive for a delay" (needs the app open), "Times look wrong" (airport's time zone, by design), "Can I add a flight months ahead?" (yes, shown as Projected until a week out), "How do I delete everything?", "Is my key safe?" (stored on this device, in app preferences; remove it any time), "Does it work on iPad / Apple Watch / with widgets?" (no); the safety line; the not-affiliated line. Under 70 lines.

---

## 4. Card spec (owner: **sonnet**) — `scripts/make_store_cards.py`

### Inputs and tooling

- **Python 3.13 + Pillow 11.1** (both present on this machine: `python --version`, `python -c "import PIL"`; note Pillow is in the user site-packages, so do not run with `-I`). No Node dependencies; `node` is v24 but has no image library installed.
- **Font: Manrope (SIL OFL), variable TTF**, downloaded once from Google Fonts' GitHub: `https://github.com/google/fonts/raw/main/ofl/manrope/Manrope%5Bwght%5D.ttf` (165 KB) into `scripts/fonts/Manrope[wght].ttf`, with `scripts/fonts/OFL.txt` fetched from `https://github.com/google/fonts/raw/main/ofl/manrope/OFL.txt`. Commit both (OFL permits it) so renders are reproducible offline. Verified here: `ImageFont.truetype(path, size).set_variation_by_name(b"ExtraBold")` works (names available: ExtraLight … ExtraBold) with Pillow's bundled FreeType 2.13.3, no raqm needed. **Fallback** if the file is missing and the download fails: `C:\Windows\Fonts\segoeuib.ttf` (headline) and `seguisb.ttf` (subline), both present, with a printed warning. Manrope's rounded-geometric heavy weight echoes the app's SF Rounded heavy type without imitating any other listing.
- **Raws**: `docs/store/raw/<scene>.png` (final captures, retaken after the UI packages), 1320 × 2868, real simulator status bar at 9:41. `--raw docs/store/raw-before` switches to the current captures for a dry run. Scenes that are missing from the raw folder are **skipped with a warning**, not an error (raw-before lacks `airportTraffic` and `delays`), and the contact sheet is built from whatever rendered.
- CLI: `python scripts/make_store_cards.py [--raw DIR] [--set 6.9|6.5|all] [--only SCENE] [--check]`. `--check` (also run at the end of every build) verifies every output's pixel size, mode RGB, no alpha, and prints a table.

### Canvas and background (6.9", 1320 × 2868)

The cards are dark because the app is dark; the phone must not look like a black hole on a black page, so each card has a two-stop vertical gradient plus a soft colour glow behind the phone in that card's accent.

- Base gradient, top → bottom: `#0B0B0F` → `#151A33` (app background to a navy a shade lighter than the icon's `#1B2450`, so the icon still reads darker than the page).
- Glow: an ellipse centred at (660, 1900), radii 820 × 1100, filled with the card's accent at 16% alpha, Gaussian-blurred radius 180. Draw it before the phone.
- Faint grid texture, optional: none. Keep it clean.
- Accents (from `Theme.swift`): blue `#4D8FFF`, green `#33D680`, orange `#FF9E26`, red `#FF474D`, purple `#A878FF`, cyan `#40C7EB`.

### Typography and caption block

- **Headline**: Manrope ExtraBold, **104 px**, white `#FFFFFF`, line height 112 px, left-aligned at x = 100, first baseline at y = 300. Max 2 lines; the spec below gives the line break with `|`. Letter-spacing −2 px (Pillow: draw per character with a kerning adjustment, or accept default — default is acceptable).
- **Subline**: Manrope Medium (`set_variation_by_name(b"Medium")`), **44 px**, white at 66% (`#FFFFFF` alpha 168 → composite to `#A9A9AF` on the dark gradient; just draw with RGBA), line height 56 px, max 2 lines, wrapped at 1120 px, starts 36 px under the headline's last line.
- **Footer**: Manrope Medium, **30 px**, white at 42%, centred at y = 2800: `Sample trip shown · Demo Mode` on cards 1, 2, 4, 5, 8; `Live data shown · times and traffic vary` on cards 3, 6, 7. On card 3 (which shows the sample flight **and** real traffic): `Sample flight shown with live traffic · Demo Mode`.
- Safe margins: nothing closer than 100 px to the left/right edges, 120 px to the top, 60 px to the bottom.

### Phone

A **framed screenshot**, not a device image (no Apple artwork):

- Scale the raw to **974 × 2116** (factor 0.738). Position: top-left at (173, 620). Bottom edge lands at 2736, leaving room for the footer.
- Clip to a rounded rectangle, radius **138 px** (the 6.9" display corner at this scale).
- Bezel: a rounded rectangle 14 px larger on every side, radius 152, filled `#1C1C24`, with a 2 px inner stroke `#FFFFFF` at 10% and a 2 px outer stroke `#000000` at 60%.
- Shadow: the bezel shape offset (0, 36), filled black at 55%, Gaussian blur 70, drawn before the bezel.
- **Status bar: keep it.** The raws carry the simulator's real status bar (9:41, full bars, Wi-Fi, 100%) and a black Dynamic Island — that is accurate and is what Apple's own examples show. Do not paint over it. Two harness notes for the retake (not for this script): (a) `codemagic.yaml` uses `--batteryState charged`, which draws a charging bolt; change to `--batteryState discharging --batteryLevel 100`; (b) `raw-before/flights.png` has a system notification banner ("Ready for Apple Intelligence") over the title — the retake must discard any raw with a banner (add a 15 s settle after the warm-up launch, and eyeball the set).
- Optional callout (card 3 only): none. The screens are strong enough; callouts age badly.

### The cards, in upload order

Filenames are `NN-slug.png`. Headline `|` marks the line break.

| # | file | scene raw | accent | headline (≤ 6 words) | subline (≤ 10 words) |
|---|---|---|---|---|---|
| 1 | `01-your-flight-live.png` | `detail` | orange | Your flight, live. | Countdown, gates, and a forecast of when you'll land. |
| 2 | `02-every-flight-one-glance.png` | `flights` | blue | Every flight, \| one glance. | Delays shown in the airport's own time zone. |
| 3 | `03-who-is-around-you.png` | `tracking` | cyan | See who's \| around you. | Real aircraft on the map, in the air and on the ground. |
| 4 | `04-will-you-make-it.png` | `connection` | red | Will you \| make it? | Connections rated from live times, not the schedule. |
| 5 | `05-passport.png` | `passport` | purple | A Passport that \| writes itself. | Miles, hours, airports, countries — from the flights you take. |
| 6 | `06-airport-status.png` | `airports` | green | Airport status, \| in plain English. | FAA delays and decoded weather. No key needed. |
| 7 | `07-taxiway.png` | `airportTraffic` | cyan | Who's ahead \| on the taxiway. | Ground traffic on satellite imagery, aircraft by aircraft. |
| 8 | `08-every-minute-lost.png` | `delays` | orange | Every minute \| lost, counted. | On-time rate and worst delays, the way the DOT counts them. |

Rules the captions obey (and `--check` greps for): no other app's name, no airline name, no price, no "AI", no "real-time", no superlatives. "DOT" stays (a US agency, factual). If a scene is missing, its number is skipped and the remaining files keep their numbers so re-runs are stable.

Order rationale: 1–3 are the three differentiators in persuasion order (the flight page is the whole app in one screen; the live map is the visual hook; the connection card is the emotional one). 4–6 broaden. 7–8 are optional: upload them only if the retake produces a busy JFK apron and a seeded delay history (ui-review §4 rows 7–8).

### 6.5" set (1284 × 2778)

Render the 6.9" card, then `Image.resize((1284, 2778), Image.LANCZOS)`. The aspect differs by 0.4% (1320/2868 = 0.4603 vs 1284/2778 = 0.4622); that is invisible and avoids a second layout. Save to `docs/store/screenshots/6.5/` with the same filenames.

### Share image `docs/store/share-image.png` (1200 × 630)

Same gradient, blue glow centred at (900, 400). Left column at x = 80: app name (Manrope ExtraBold 76 px, the brand word as a `BRAND` constant at the top of the script, default `Overwing`), subline "Your flight, live — with a forecast that shows its working." (Manrope Medium 30 px, white 66%, wrap at 560 px), then a row of three chips (`Free`, `No account`, `iPhone`): 24 px Medium, white 80%, in `#232330` capsules with a 1 px `#FFFFFF` 10% stroke. Right: two framed screenshots, `detail` at 0.17 scale (224 × 488) rotated 0°, top-left (700, 90), and `tracking` at the same scale at (900, 160), both clipped at the canvas bottom (they bleed off), each with the bezel/shadow treatment at the smaller radius (32 px). No icon (it is being regenerated in P1; the script takes `--icon PATH` to add it later at 120 px, top-right at (1000, 60), rounded 27 px — leave the hook in, off by default).

### Contact sheet `docs/store/contact-sheet.png`

All rendered 6.9" cards at 20% (264 × 574) in two rows of four on `#0B0B0F`, 40 px gutters, filename under each in Manrope Medium 20 px white 60%, a title row "Store cards · 6.9-inch · built <date>". Width 1296 + margins = 1376 px; height ≈ 1340. Not for upload.

### Output tree

```
docs/store/screenshots/6.9/01-… 08-….png   1320 × 2868, RGB
docs/store/screenshots/6.5/01-… 08-….png   1284 × 2778, RGB
docs/store/share-image.png                1200 × 630
docs/store/contact-sheet.png
scripts/make_store_cards.py
scripts/fonts/Manrope[wght].ttf, scripts/fonts/OFL.txt
```

Dry-run acceptance: `python scripts/make_store_cards.py --raw docs/store/raw-before --set all` produces six cards per set (scenes 7 and 8 skipped with a warning), the share image and the contact sheet, and `--check` passes. The sonnet builder views at least cards 1, 3 and 5 at full size (Read the PNG) and fixes anything that overlaps or clips before reporting.

---

## 5. Files to produce, with owners

Ownership is disjoint. Nobody edits `docs/ui-review.md`, `docs/privacy-policy.md`, the Swift sources, or this file.

| File | Owner | Spec | Notes |
|---|---|---|---|
| `docs/store/listing.md` | **opus** | §3 | All copy, the three name options, counts in the checker format, categories, age rating table, copyright, URLs, screenshots table (filenames from §4), App icon note, other ASC answers, TestFlight fields, decisions list |
| `docs/store/app-privacy-answers.md` | **opus** | §3 | "Data Not Collected" with the reasoning table; the missing privacy-manifest item |
| `docs/store/review-notes.md` | **opus** | §3 | App Review notes + TestFlight beta description, What to Test, contact placeholders, content-rights answer, reviewer walk-through |
| `docs/store/support.md` | **opus** | §3 | Support page text |
| `scripts/check_listing.py` | **sonnet** | below | Run `python scripts/check_listing.py --write` once opus has finished, then verify. Coordinate: opus writes placeholder `Count:` lines in the right shape; sonnet's script rewrites them |
| `scripts/make_store_cards.py`, `scripts/fonts/*` | **sonnet** | §4 | Pillow; dry run on raw-before |
| `docs/store/screenshots/6.9/*`, `docs/store/screenshots/6.5/*`, `docs/store/share-image.png`, `docs/store/contact-sheet.png` | **sonnet** | §4 | Dry-run outputs from raw-before are committed by the parent so the README has something to show; they are regenerated from `docs/store/raw/` after the retake |
| `README.md` — new final section **"App Store"** only | **sonnet** | below | Nothing above the new section changes |

**`scripts/check_listing.py`** (port of ride-compare's `check-listing.mjs`, stdlib only): parse the `<!-- limit: … -->` fields; count code points for chars and UTF-8 for bytes; `--write` rewrites counts; required fields: `name-1 name-2 name-3 subtitle promotional-text description keywords whats-new review-notes beta-description what-to-test`; fail on: any limit exceeded; a wrong printed count; a forbidden name in `name-*`, `subtitle`, `keywords`, `promotional-text` (regex, case-insensitive: `flighty|flightradar|flightaware|radar24|tripit|app in the air|delta|united|american airlines|alaska air|southwest|jetblue|british airways|lufthansa|air france|klm|emirates|qantas|ryanair|easyjet|apple`); any keyword ≤ 2 chars, with surrounding spaces, repeated, or whose word (or its `s` plural) appears in any name option or the subtitle; description missing "not an air-traffic-control tool" or "not affiliated with"; description or promo text containing `Live Activit|widget|Apple Watch|push notification|real-time|AI-powered` (features that do not exist / banned phrasing). Exit 1 with every problem listed. Print the table of counts on success. Windows-safe (no ANSI colours needed, `\r\n` tolerated).

**README "App Store" section** (append at the very bottom, before the closing `<div align="center">` footer is fine, or after it — keep the existing footer intact): heading `## App Store`, one sentence on status (TestFlight public link first, store later), a thumbnail row of cards 1–6 from `docs/store/screenshots/6.9/` at `width="15%"` each inside a centred `<div>`, then a bullet list linking `docs/store/listing.md`, `docs/store/review-notes.md`, `docs/store/app-privacy-answers.md`, `docs/store/support.md`, `docs/privacy-policy.md`, `docs/store/store-review.md` (this file), and the two commands (`python scripts/check_listing.py`, `python scripts/make_store_cards.py --raw docs/store/raw-before`). Do not name Flighty in this section.

---

## 6. Owner decisions

Short list; recommended answer first.

1. **Store name.** Recommended: rename to **Overwing** ("Overwing: Flight Tracker"), verified by saving it in ASC and a USPTO search. Alternatives: Holdshort; or keep "FlightDeck: Flights & Passport" and accept the collision with id 6759628645. "Prad's Flight Deck" is for the private TestFlight phase only. The rename touches `CFBundleDisplayName`, the Welcome title, the About footer, the privacy policy title and the README.
2. **Subtitle.** Recommended: "Live map, delay odds, Passport".
3. **Support URL and contact email** (required for both TestFlight external testing and the store). Cheapest: a GitHub Pages site on the repo (or a public `docs/` on a new public repo if `flighty-pro` stays private) hosting `support.md` and `privacy-policy.md`; a dedicated address such as a plus-alias or an iCloud Hide-My-Email alias for the feedback/support email. The TestFlight feedback pipeline is unaffected.
4. **Privacy policy URL.** `docs/privacy-policy.md` exists; it must be on a public web page before external TestFlight. Same hosting as item 3. `SettingsView` already links `https://pbswimmer3.github.io/flighty-pro/privacy` with a `TODO(owner): confirm hosted URL` — either make that page exist (GitHub Pages on this repo) or change the constant; paste the same URL into ASC.
5. **Price and availability.** Free, no in-app purchases. Availability: all countries is fine (nothing in the app is region-locked; FAA status is US-only and the copy says so). If the owner prefers a small footprint for TestFlight: US + UK.
6. **Category.** Primary **Travel** (where every consumer flight tracker lives). Secondary **Utilities**. Not Navigation: the copy says in the same breath that this is not a navigation tool.
7. **Age rating.** Answer the lowest option everywhere: no parental controls, no age assurance, no unrestricted web access (the only links open Safari for the privacy policy and RapidAPI), no user-generated content, no social, no messaging, no advertising, no mature/medical/sexual/violent/gambling content. Expected **4+**.
8. **iPad.** `TARGETED_DEVICE_FAMILY = "1,2"` with all iPad orientations enabled, and no layout has been seen on iPad. Recommended: iPhone only for 1.0 (`TARGETED_DEVICE_FAMILY = 1`, drop the iPad orientation lines) — a two-line pbxproj change, in a code package, before the store build. Until then, do not claim iPad in copy.
9. **Privacy manifest.** Add `PrivacyInfo.xcprivacy` (UserDefaults, CA92.1; tracking false; no collected data). Code package; small.
10. **Screenshots 7 and 8.** Upload them only if the retake produces a busy JFK apron and the seeded Passport history described in `docs/ui-review.md` §4; otherwise ship six.
11. **TestFlight public link settings.** Tester limit (suggest 100 to start), "What to Test" per build, and whether to require a build-by-build approval. The first external build goes through Beta App Review (usually under 48 h); the notes in `review-notes.md` are written for that reviewer too.
12. **Copyright line.** `2026 <owner's name as it should appear>` (Apple adds the ©).
