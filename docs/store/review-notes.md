# Flight Dash: App Review and TestFlight Beta Review notes

Everything the reviewers are asked for, in paste order. Checked against the code at HEAD of `claude/app-store-prep` on 2026-11-11. Fill every `<<OWNER: …>>` before pasting. If the store name changes, replace "Flight Dash" in the blocks below.

## 1. App Review notes

Paste into App Store Connect → (version) → App Review Information → Notes. Sign-in required: **No**. Limit 4000 bytes.

### App Review notes (4000 bytes)
```text
NO SIGN-IN IS NEEDED. Flight Dash has no account system and no server.

HOW TO SEE EVERYTHING (Demo Mode, on by default, about three minutes)
1. Launch the app. A Welcome sheet explains the sample trip. Tap "Explore the sample trip".
2. Flights tab: four sample flights built around the current time: one in the air now (SFO to JFK), a connection later today (JFK to LHR), one tomorrow (ORD to AUS), one that landed yesterday (LAX to SFO, under Passport > Past Flights). A "Demo Mode" banner says these are samples with made-up times.
3. Tap the flight in the air. The page shows a route map, the stage bar, the Arrival Forecast card (tap "What's driving this" for the factors), the timeline, gates and weather. Tap "Track this flight" for the live map and switch between Ground, Nearby and Route.
4. Connection tab: the JFK connection rated from live times.
5. Passport tab: lifetime stats, route map, and the Delay Tracker.
6. Airports tab > JFK: live FAA status, decoded weather, and "Airport-Wide Traffic".
7. Settings: Flight Alerts (with "Send a Test Alert"), the Demo Mode switch, the AeroDataBox key field, Privacy Policy and Acknowledgements.

Samples are labelled on screen: the Demo Mode banner on the Flights, Connection and Passport tabs, a "Sample" badge on demo search results, and a note on the forecast when it uses generated history. Airport status, weather and aircraft positions are real even in Demo Mode, so they change from minute to minute.

WHY THERE IS NO DEMO ACCOUNT
There is no account to give. Live lookups by flight number need the user's own free AeroDataBox key (RapidAPI Basic plan). We ask that the built-in Demo Mode be accepted in lieu of a demo account (Guideline 2.1(a)). A real flight can also be added without a key: Add Flight > "Add your real flight".

DATA AND PRIVACY
Requests go straight from the iPhone to public services: nasstatus.faa.gov (airport status), aviationweather.gov (an airport code), api.adsb.lol (a callsign, or a map area around an airport or the flight's estimated position), api.adsbdb.com (a callsign), and, only with the user's own key, aerodatabox.p.rapidapi.com (flight number and date). There is no server of ours, no analytics, no ads, no third-party SDK. Flights and settings stay on the device. Notifications are local. The app does not ask for location. App Privacy: Data Not Collected.

ALERTS
Check-in, boarding, gate-close, departure, landing and baggage alerts are scheduled on the device and fire with the app closed. Delay and gate-change alerts are found when the app refreshes, so they need the app open; Settings says so.

SAFETY
Aircraft positions are estimates. The app says it is not an air-traffic-control tool and must not be used for navigation, in Settings > About and on the Airport-Wide Traffic screen.

THIRD-PARTY CONTENT
Airport list from mwgg/Airports under the MIT License; the notice is in Settings > Acknowledgements with the data sources. Airlines appear as plain text and two-letter monograms, no logos. The app is not affiliated with any airline or data provider.

Contact: <<OWNER: first and last name>>, <<OWNER: email>>, <<OWNER: phone with country code>>
```

Count: **3159 / 4000 bytes**

## 2. App Review contact

| Field | Value |
| --- | --- |
| First name | `<<OWNER: first name>>` |
| Last name | `<<OWNER: last name>>` |
| Phone | `<<OWNER: phone, with country code>>` |
| Email | `<<OWNER: email>>` |
| Sign-in required | No |

## 3. TestFlight: Test Information

Paste into TestFlight → Test Information. Same text as `listing.md`.

**Beta App Description** (paste into "Beta App Description"):

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

**What to Test** (paste per build, under the build's "What to Test"):

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

| TestFlight field | Value |
| --- | --- |
| Feedback email | `<<OWNER: feedback email>>` |
| Marketing URL | leave empty |
| Privacy Policy URL | `<<OWNER: hosted privacy policy URL>>` (required for external testing; must match the link in Settings) |
| Beta App Review contact: first name, last name, phone, email | same as section 2 |
| Sign-in required | No |
| Beta App Review notes | paste the App Review notes block from section 1 |

## 4. Export compliance

Already answered in the build: `ITSAppUsesNonExemptEncryption = NO` (the app only uses HTTPS through iOS). No document upload needed.

## 5. Content rights

"Does your app contain, show, or access third-party content?" → **Yes**, and you have the rights to use it:

- Public US government data: FAA airport status (nasstatus.faa.gov), NOAA Aviation Weather Center METARs.
- Community ADS-B positions from adsb.lol and callsign routes from adsbdb.com, both public APIs.
- AeroDataBox data, fetched only with the user's own key under the user's own RapidAPI subscription.
- Airport list from mwgg/Airports, MIT License.

All are credited in Settings → Acknowledgements. No airline logos.

## 6. Reviewer walk-through (checklist)

- [ ] Welcome sheet appears on first launch; "Explore the sample trip" closes it
- [ ] Demo Mode banner on Flights, Connection and Passport
- [ ] Flight in the air: forecast card, "What's driving this", "Track this flight"
- [ ] Tracking map: Ground, Nearby, Route; tap an aircraft to identify it
- [ ] Connection tab rates the JFK connection
- [ ] Passport and Delay Tracker count the sample flights
- [ ] Airports → JFK: FAA status, weather, Airport-Wide Traffic
- [ ] Settings: alerts, Send a Test Alert, Demo Mode, key field, Privacy Policy link, Acknowledgements
- [ ] Add Flight → "Add your real flight" works without a key

## 7. Known limitations the reviewer may hit

- **Empty live map.** ADS-B coverage comes from volunteers. At a quiet airport, or when the free adsb.lol quota is low, the map can show "No ADS-B coverage here". Big US airports such as JFK are the best test.
- **FAA status is US-only.** Non-US airports show weather but no FAA programs.
- **Times move with the clock.** The sample trip is rebuilt around the current time, so the numbers and stages differ from the screenshots.
- **Change alerts need the app open.** A delay or gate change is only noticed when the app refreshes.
- **Privacy Policy link.** It opens Safari at the hosted policy; **OWNER:** make sure that page is live before submitting.
