# Flight Dash support

## Contact

- Bug reports: [open an issue](https://github.com/pbswimmer3/flight-dash/issues)
- TestFlight testers: take a screenshot in the app and choose **Send Beta Feedback**.

## Getting started

1. Open the app. The Welcome sheet explains what you are looking at; tap **Explore the sample trip**.
2. You start in **Demo Mode**: a sample trip with made-up flights, labelled on screen. Airport status, weather and live aircraft are always real.
3. Add a real flight by hand: **Add Flight → Add your real flight**. No key needed.
4. For lookups by flight number, get a free AeroDataBox key:
   1. Sign up at rapidapi.com.
   2. Find AeroDataBox and subscribe to the free **Basic** plan.
   3. Copy your RapidAPI key.
   4. In Flight Dash, open **Settings**, paste it under **Live flight lookups**, and turn off **Demo Mode**.

## Common questions

**Why do I see flights I didn't add?**
That is the sample trip from Demo Mode. Remove a flight from its page (••• menu → Remove Flight), or all of them with Settings → Remove All Flights. To bring the samples back, tap **Load Sample Trip** on the empty Flights tab.

**How do I track a real flight?**
Add it by hand, or add your free AeroDataBox key (above) and search by flight number. Pull down on a flight to refresh it.

**The map says "No ADS-B coverage here".**
Live aircraft positions come from a volunteer receiver network. Big airports are well covered; smaller ones can have gaps. The app says so instead of showing an empty sky.

**An alert didn't arrive for a delay or a gate change.**
Those are found when the app refreshes, so Flight Dash needs to be open. Boarding, gate-close, departure, landing and baggage alerts are scheduled on your iPhone and arrive with the app closed.

**The times look wrong.**
Every time is shown in the airport's own time zone, as on your boarding pass. A departure from New York shows New York time even if you are in London.

**Can I add a flight months ahead?**
Yes. If the live feed doesn't reach that date yet (about a week ahead on the free plan), it is shown as **Projected** from this week's timetable and switches to the real schedule once it is in range and you open the app.

**How do I delete everything?**
Settings → **Remove All Flights** (this also clears your Passport) and **Clear Punctuality History**. Deleting the app removes everything, including your key.

**Is my key safe?**
It is stored on this device, in the app's preferences, and is only sent to AeroDataBox with your own lookups. Clear the field in Settings to remove it any time.

**Does it work on iPad, Apple Watch or with widgets?**
No. Flight Dash is an iPhone app (iOS 17 or later) with no widgets or Watch app.

**Does it collect my data?**
No. There is no account, no server, no analytics and no ads, and the app never asks for your location. See the privacy policy: https://pbswimmer3.github.io/flight-dash/privacy/.

## Safety

Positions shown on maps are estimates. Flight Dash is not an air-traffic-control tool and must never be used for navigation or separation.

## About

Flight Dash is an independent app. It is not affiliated with, endorsed by or sponsored by any airline, airport or data provider. Airport status comes from the FAA, weather from NOAA, live aircraft positions from the adsb.lol community network, routes from adsbdb, and flight schedules from AeroDataBox when you add your own key.
