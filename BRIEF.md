# FlightDeck
My personal flight tracker for iPhone, built without a Mac.
**Now:** New UI and a full App Store kit are ready in a pull request. Nothing is live yet.
**Next:** Pick the store name: reply "Overwing" or name another. ~2 min
Updated 2026-11-11

## Needs you
- [ ] **Pick the App Store name**: "FlightDeck - Flight Tracker" is taken by another app. ~2 min
  1. Read section 2 of [store-review.md](docs/store/store-review.md) (3 ranked options)
  2. Reply with your pick (recommended: "Overwing: Flight Tracker")
- [ ] **Look at the new screens and store cards**: they are rendered from the cloud simulator. ~5 min
  1. Open [contact-sheet.png](docs/store/contact-sheet.png)
  2. Good looks like: no screen looks broken, text is readable
- [ ] **Merge the pull request**: merging uploads a new TestFlight build for you. ~2 min
  1. Open the "App Store prep" pull request on GitHub and press Merge
  2. Install the new build from TestFlight and tap through each tab
- [ ] **Fill in the contact details**: Apple needs a name, phone and email for review. ~5 min
  1. Open [review-notes.md](docs/store/review-notes.md) and replace each `<<OWNER: …>>`

## Later
- [ ] **Host the privacy policy**: the app links to pbswimmer3.github.io/flighty-pro/privacy. ~10 min
- [ ] **Open outside testing**: Claude can make the public link and send build 6+ to Apple once you say go. ~5 min

## What changed
- ✅ **Every screen reworked.** Welcome sheet, "sample" labels, bigger-text support, VoiceOver labels, new icon.
- ✅ **Compiles and runs.** Codemagic built it and captured 9 screens with no errors.
- ✅ **App Store kit.** 8 screenshot cards (2 sizes), listing copy, review notes, privacy answers, support page.
- ✅ **Privacy manifest and Acknowledgements screen added.** Both are Apple requirements.
- ⚠️ **Not tried on your phone yet.**

## Decisions
- **2026-11-11 · iPhone-only for version 1** _(auto)_
  - Why: no layout was checked on iPad; reviewers test there.
  - Undo: TARGETED_DEVICE_FAMILY back to "1,2" in the Xcode project.
- **2026-11-11 · Recommended renaming to "Overwing: Flight Tracker"** _(auto)_
  - Why: the FlightDeck name is taken on the store.
  - Undo: pick another name; the copy says which fields to change.
- **2026-11-11 · Work happens on a branch, not main** _(auto)_
  - Why: every push to main uploads a TestFlight build.
  - Undo: merge or close the pull request.

## More
- UI review: [docs/ui-review.md](docs/ui-review.md)
- Store plan: [docs/store/store-review.md](docs/store/store-review.md)
- Listing copy: [docs/store/listing.md](docs/store/listing.md)
