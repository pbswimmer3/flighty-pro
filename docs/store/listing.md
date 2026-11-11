# Flight Dash: App Store listing (draft for the owner)

> **Name chosen by the owner (2026-11-11): Flight Dash.** Home Screen name "Flight Dash"; store name "Flight Dash: Flight Tracker". The Xcode target, folders and bundle id keep the code name `FlightDeck` / `com.personal.flightdeck` (users never see them).

Everything App Store Connect asks for on the product page and in TestFlight, ready to paste. Written 2026-11-11 on branch `claude/app-store-prep`, against version 1.0 (build number set by Codemagic per upload). Bundle id `com.personal.flightdeck`, ASC app id 6828448145, iPhone only, iOS 17+.

- Each field sits under a `### <Field> (<limit>)` heading, in a `text` block holding exactly what you paste. Counts are checked by `python scripts/check_listing.py` and rewritten by `python scripts/check_listing.py --write`. Do not edit a count by hand.
- Body copy says "Flight Dash", the Home Screen name (`CFBundleDisplayName`).
- Items marked **OWNER** need a login, a decision or a real iPhone.
- Card images are built by `python scripts/make_store_cards.py` (see "Screenshots").

## Rules this listing follows, and where they come from

| Rule | Source |
| --- | --- |
| Name 2 to 30 characters; subtitle 30 at most; privacy policy URL required for iOS apps | [App information](https://developer.apple.com/help/app-store-connect/reference/app-information) |
| Promotional text 170 characters; description 4000 characters, plain text; keywords 100 bytes, comma-separated, each longer than two characters, no other apps' or companies' names; What's New 4000 characters, not shown for a first version; review notes 4000 bytes; copyright is the year and owner (Apple adds the ©); support URL required | [Platform version information](https://developer.apple.com/help/app-store-connect/reference/platform-version-information) |
| Screenshots 1 to 10 per size, PNG or JPEG, no alpha; 6.9-inch accepts 1320 × 2868; 6.5-inch accepts 1284 × 2778 | [Screenshot specifications](https://developer.apple.com/help/app-store-connect/reference/screenshot-specifications) |
| Age rating questions and resulting ratings | [Age ratings values and definitions](https://developer.apple.com/help/app-store-connect/reference/age-ratings-values-and-definitions) |
| **2.1(a)** demo account, or a built-in demo mode in lieu of one with Apple's approval | [App Review Guidelines](https://developer.apple.com/app-store/review/guidelines/) |
| **2.3** metadata must reflect the app's core experience; **2.3.1** no hidden or undocumented features, describe new features specifically in the review notes | same |
| **2.3.3** screenshots show the app in use; **2.3.7** no trademarked terms or popular app names in metadata, subtitle makes no unverifiable claims; **2.3.9** fictional data instead of a real person's | same |
| **4.1** no copycat apps, no other developer's name or brand in the name; **5.2.1** no third-party trademarks without permission, nothing confusingly similar; **5.2.4** do not imply Apple endorses the app | same |

How they were applied: no other flight app and no airline is named in the name, subtitle, keywords or promotional text. The description names data sources (FAA, NOAA, adsb.lol, adsbdb, AeroDataBox) only to say where data comes from, and ends with the not-affiliated line. No feature is claimed that is not in the code at HEAD: no Live Activities, widgets, Apple Watch, push notifications, iPad layout, accounts or sync.

## Name

**Chosen by the owner: Flight Dash** (2026-11-11). "FlightDeck - Flight Tracker" (id 6759628645, JAC LLC) already exists, so the code name was not used. An App Store search for "Flight Dash" on 2026-11-11 (US, UK, CA, AU, IN, DE, JP) found no app with that name. Final check: App Store Connect rejects a taken name when you save it; a USPTO trademark search is still worth a minute.


### Name (30)
```text
Flight Dash: Flight Tracker
```

Count: **24 / 30 characters**

Earlier candidates (not used): Overwing: Flight Tracker, Holdshort: Flight Tracker (see `store-review.md` section 2).

## Subtitle

### Subtitle (30)
```text
Live map, delay odds, Passport
```

Count: **30 / 30 characters**

| Rank | Subtitle | Count |
| --- | --- | --- |
| 1 | Live map, delay odds, Passport | 30 / 30 |
| 2 | Track, forecast, remember | 25 / 30 |
| 3 | No account. No subscription. | 28 / 30 |

## Promotional text

Can be changed at any time without a new version.

### Promotional text (170)
```text
Your flight, live: a countdown to boarding, a forecast of when you'll really land, real aircraft around you on the map, and a Passport built from every flight you take.
```

Count: **168 / 170 characters**

## Description

### Description (4000)
```text
Your flight, live, with a forecast that shows its working and a Passport that writes itself. Flight Dash is free: no account, no subscription, no server, and your flights stay on this iPhone.

YOUR FLIGHT, LIVE
• A card per flight with status, progress and a countdown to the next step.
• Times in the airport's own time zone. When one moves, the old time stays, struck through.
• The flight page: route map, terminals, gates, baggage claim, a timeline, the aircraft and weather at both ends.
• Check-in, boarding, gate-close, departure, landing and baggage alerts are scheduled on your iPhone and arrive with the app closed. Delay and gate-change alerts need the app open.

A FORECAST THAT SHOWS ITS WORKING
• The chance you land 15 or more minutes late, a forecast arrival time and the likely window.
• A statistical model built from a 60-day punctuality record, adjusted for FAA delay programs and low-visibility weather. It names its sample size and every factor that moved the number.

EVERY AIRCRAFT AROUND YOU
• Your aircraft on its route with the real traffic around it, from ADS-B (the positions aircraft broadcast).
• Three views: Ground (5 nautical miles, satellite, the queue for the runway), Nearby (40) and Route. Tap any aircraft to see who it is.
• Positions between reports are estimated, and labelled as such. Coverage comes from a volunteer network: good at big airports, sometimes empty elsewhere, and the app says so.

WILL YOU MAKE THE CONNECTION?
• Connections are found automatically and rated Relaxed to Misconnect from live times, against the airport's minimum connection time, plus 15 minutes for a terminal change.

A PASSPORT THAT WRITES ITSELF
• Flights, miles, hours, airports, countries and airlines, per year or all time, with a route map and records.
• A Delay Tracker at the US DOT 15-minute threshold: time lost, on-time rate, worst airlines and airports.
• Searchable past flights. Computed from your flights, so delete one and every number follows.

AIRPORTS
• 110 airports in 49 countries built in, with terminals and connection times; search about 7,900 more.
• FAA ground stops and delay programs for US airports, in plain English.
• Decoded weather worldwide from the METAR (the airport weather report).
• Airport-Wide Traffic on satellite imagery.

HOW IT GETS ITS DATA
• Demo Mode is on at first: a sample trip built around the current time, labelled on screen. Airport status, weather and live aircraft are always real.
• Add real flights by hand, no key needed.
• For lookups by flight number, add your own free AeroDataBox key (from RapidAPI) in Settings. It reaches about a week ahead; later flights show as Projected and update once in range.

PRIVATE BY DESIGN
• No account, no server, no analytics, no ads, no tracking.
• Flights, settings and your key are stored on this device. Requests go straight from your phone to the data services. Alerts are local. No location access.

GOOD TO KNOW
• iPhone, iOS 17 or later. FAA programs are US-only. Live aircraft coverage varies.

Positions shown on maps are estimates. Flight Dash is not an air-traffic-control tool and must never be used for navigation or separation.

Flight Dash is an independent app. It is not affiliated with, endorsed by or sponsored by any airline, airport or data provider. Airport status comes from the FAA, weather from NOAA, live aircraft positions from the adsb.lol community network, routes from adsbdb, and flight schedules from AeroDataBox when you add your own key.
```

Count: **3492 / 4000 characters**

## Keywords

Comma-separated, no spaces. No word that is already in a name option or the subtitle (Apple indexes those): `overwing`, `holdshort`, `flightdeck`, `flight(s)`, `tracker`, `passport`, `live`, `map`, `delay(s)`, `odds` are left out. No other app's name, no airline, no `free` or `app`.

### Keywords (100)
```text
status,airport,gate,boarding,layover,connection,adsb,metar,faa,miles,avgeek,logbook,plane,aviation
```

Count: **98 / 100 bytes**

## What's New (version 1.0)

Apple does not show this for a first version. Kept for 1.0.1, or in case App Store Connect asks.

### What's New (4000)
```text
The first release of Flight Dash. Track your flights live with a countdown to boarding, an arrival forecast that shows its working, real aircraft around you on the map, connection ratings, airport status and weather, and a Passport built from the flights you take. It opens in Demo Mode with a sample trip, so there is nothing to set up.
```

Count: **336 / 4000 characters**

## TestFlight

Paste into TestFlight → (the app) → Test Information. Both texts are repeated in `review-notes.md` with the rest of the Beta App Review answers.

### Beta App Description (4000)
```text
Flight Dash tracks the flights you take. Each flight gets a live card with a countdown to the next step, an arrival forecast that shows its working, and a live map of the real aircraft around yours. Every flight you take is added to a Passport of miles, hours, airports and delays.

You need nothing to try it. The app opens in Demo Mode with a sample trip built around the current time. Those flights are made up and labelled Demo Mode on screen; airport status, weather and live aircraft are real.

To add a real flight, tap Add Flight, then Add your real flight, and type it in. For lookups by flight number, get a free AeroDataBox key:
1. Sign up at rapidapi.com.
2. Find AeroDataBox and subscribe to the free Basic plan.
3. Copy your RapidAPI key.
4. In Flight Dash, open Settings, paste it under Live flight lookups, and turn off Demo Mode.

Not in this build: Live Activities, widgets, Apple Watch, push notifications. Delay and gate-change alerts need the app open.

Positions on maps are estimates. Flight Dash is not an air-traffic-control tool.

Feedback: take a screenshot in the app and choose Send Beta Feedback, or use the TestFlight app. Your feedback goes to the developer's issue tracker.
```

Count: **1203 / 4000 characters**

### What to Test (4000)
```text
1. Open the app. Read the Welcome sheet, tap Explore the sample trip, and check the Demo Mode banner is there.
2. Open the flight that is in the air. Read the Arrival Forecast and "What's driving this". Tap Track this flight and try Ground, Nearby and Route. Live aircraft coverage varies by airport.
3. Settings: turn on Flight Alerts and tap Send a Test Alert. Then close the app and check the boarding alert for the sample connection arrives (it is a few hours away).
4. Connection tab: check the layover rating makes sense.
5. Passport: open the Delay Tracker and switch between years.
6. Airports: open JFK and then Airport-Wide Traffic.
7. Add a flight by hand dated yesterday. Check the Passport counts it, then remove it (flight page, ••• menu) and check the numbers go back.
8. If you have a key: add a real flight by number and pull to refresh.
9. Set Larger Text in iOS Settings and try VoiceOver on the flights list.

Please report anything that says "HTTP", any blank screen, and any time shown in the wrong time zone.
```

Count: **1031 / 4000 characters**

TestFlight fields that are not text blocks:

| Field | Answer |
| --- | --- |
| Feedback email | **OWNER:** `<<OWNER: feedback email>>` |
| Marketing URL (optional) | leave empty |
| Privacy Policy URL | **OWNER:** the hosted `docs/privacy-policy.md` (required for external testing). Must match the link in Settings, today `https://pbswimmer3.github.io/flighty-pro/privacy` |
| Beta App Review contact | see `review-notes.md` |
| Sign-in required | No |

## Categories

- Primary: **Travel**.
- Secondary: **Utilities**. Not Navigation: the copy says the app must never be used for navigation.

## Age rating questionnaire

Answer every question with the lowest option. Match the exact labels in App Store Connect.

| Group | Question | Answer |
| --- | --- | --- |
| In-App Controls | Parental Controls | No |
| In-App Controls | Age Assurance | No |
| Capabilities | Unrestricted Web Access | No. The only links open Safari for the privacy policy and iOS Settings; there is no web view |
| Capabilities | User-Generated Content | No |
| Capabilities | Social Media | No |
| Capabilities | Messaging and Chat | No |
| Capabilities | Advertising | No |
| Mature Themes | Profanity or Crude Humor; Horror/Fear Themes; Alcohol, Tobacco, or Drug Use or References | None |
| Medical or Wellness | Medical or Treatment Information; Health or Wellness Topics | None |
| Sexuality or Nudity | all questions | None |
| Violence | all questions | None |
| Chance-Based Activities | Gambling; Simulated Gambling; Contests; Loot Boxes | None |

Expected result: **4+**.

## Copyright

```text
2026 <<OWNER: your name or company, as it should appear on the App Store>>
```

Apple adds the © sign.

## URLs (OWNER)

| Field | Status |
| --- | --- |
| Support URL (required) | **OWNER:** host `docs/store/support.md` publicly (GitHub Pages is cheapest) and fill in its contact email |
| Privacy Policy URL (required) | **OWNER:** host `docs/privacy-policy.md`. `SettingsView` links `https://pbswimmer3.github.io/flighty-pro/privacy` (marked `TODO(owner)`); make that page exist or change the constant, then paste the same URL here |
| Marketing URL (optional) | leave empty, or a one-page site; `docs/store/share-image.png` (1200 × 630) is its link preview |

## Screenshots

Built by `python scripts/make_store_cards.py` from raw captures in `docs/store/raw/` (dry run: `--raw docs/store/raw-before`). The sample trip is fictional data (2.3.9); each card's footer says whether it shows the sample trip or live data.

| # | File | Headline | Line under it | Screen |
| --- | --- | --- | --- | --- |
| 1 | `01-your-flight-live.png` | Your flight, live. | Countdown, gates, and a forecast of when you'll land. | Flight page |
| 2 | `02-every-flight-one-glance.png` | Every flight, one glance. | Delays shown in the airport's own time zone. | Flights tab |
| 3 | `03-who-is-around-you.png` | See who's around you. | Real aircraft on the map, in the air and on the ground. | Tracking map |
| 4 | `04-will-you-make-it.png` | Will you make it? | Connections rated from live times, not the schedule. | Connection tab |
| 5 | `05-passport.png` | A Passport that writes itself. | Miles, hours, airports, countries — from the flights you take. | Passport |
| 6 | `06-airport-status.png` | Airport status, in plain English. | FAA delays and decoded weather. No key needed. | Airport page |
| 7 | `07-taxiway.png` | Who's ahead on the taxiway. | Ground traffic on satellite imagery, aircraft by aircraft. | Airport-Wide Traffic (optional) |
| 8 | `08-every-minute-lost.png` | Every minute lost, counted. | On-time rate and worst delays, the way the DOT counts them. | Delay Tracker (optional) |

| Set | Folder | Size | ASC slot |
| --- | --- | --- | --- |
| 6.9-inch | `docs/store/screenshots/6.9/` | 1320 × 2868 | iPhone 6.9" display |
| 6.5-inch | `docs/store/screenshots/6.5/` | 1284 × 2778 | iPhone 6.5" display |
| Share image | `docs/store/share-image.png` | 1200 × 630 | not uploaded; link previews |
| Contact sheet | `docs/store/contact-sheet.png` | reduced | not uploaded |

**OWNER:** upload 7 and 8 only if the retake shows a busy JFK apron and a seeded delay history; otherwise ship six. No iPad set: the app is iPhone only (`TARGETED_DEVICE_FAMILY = 1`).

## App icon

The icon ships inside the build (asset catalog, regenerated by `scripts/make_icon.py` in UI P1), not as a separate upload. It must be 1024 × 1024, no alpha, square corners. It carries no airline or other app's mark.

## Other App Store Connect answers

- Price: **Free**, no in-app purchases. Availability: all countries (nothing is region-locked; the copy says FAA status is US-only).
- Content rights: **Yes**, the app shows third-party content (public FAA, NOAA and ADS-B data, adsbdb routes, MIT-licensed airport data, and AeroDataBox data under the user's own key). Attribution is in Settings → Acknowledgements. Details in `review-notes.md`.
- App Privacy: **Data Not Collected**. Reasoning in `app-privacy-answers.md`.
- Export compliance: `ITSAppUsesNonExemptEncryption = NO` is already set (HTTPS only).
- Privacy manifest: `FlightDeck/PrivacyInfo.xcprivacy` is in the project (no tracking, no collected data, UserDefaults reason CA92.1).

## Decisions made for the owner (all reversible)

1. Store name "Flight Dash: Flight Tracker" (owner, 2026-11-11). Set it in App Store Connect → App Information → Name.
2. Subtitle "Live map, delay odds, Passport"; keywords chosen to avoid every word in all three name options and that subtitle.
3. Travel primary, Utilities secondary.
4. The "late inbound aircraft" forecast factor is left out of the copy: inbound-flight data only exists in Demo Mode today, so it would not be true for a real flight.
5. The description does not name the sample trip's airline or flight numbers.
6. Free, all countries.
