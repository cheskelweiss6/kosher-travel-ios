# Kosher Travel: PRODUCT STATUS (one shared record: website + iOS)

This is the ONE record for the product: the rules, design standards, the feature table, the shared-data check,
gaps, deliberate differences, outstanding changes, known bugs and the regression checklist. Update it with every change.
It replaces, as the place to look first: the older feature inventory, checklists and worker status notes. Those stay as history.
The line-by-line detail still lives in the parity checklist (written early Oct 23 against the old native
snapshot e43410c; many of its "no" lines are now done, see the table below) and the city-page audit.

Last updated: Oct 23 2026, ~16:00 UTC, read from code only:
- Website = kosher-travel-app main 5943342 (15:27 UTC). Live at www.yourkoshertravel.com.
- Capacitor app = native-app branch d9cca16 (15:28 UTC, automatic merge of main) and its live updates.
- Native iOS = kosher-travel-ios ios-feature/shell 295cd7b (15:31 UTC). TestFlight 172 is out; 203 was triggered 15:30 UTC (Apple processing not confirmed here).
- AI server = kosher-travel-ai.sites.tab.bot (source = repo chat-api/_worker.js, same bytes as the published server).

Words used in the table: "native" = built in SwiftUI; "embedded" = the live website shown inside the native app (same code
as the website, so it changes when the website changes); "missing" = not in that version.

---

## 1. The rules (Cheskel, Oct 23 2026, verbatim)

### 11:42 AM: CRITICAL PROJECT RULE: ONE UNIFIED PRODUCT

Treat my website and native iOS app as two versions of one unified product. All development, design, feature improvements, bug fixes, and testing must follow one coordinated plan.

Do not treat the website and native app as unrelated projects, and do not maintain conflicting sets of development instructions.

Before making any changes, inspect both versions and understand their existing functionality. Preserve all working features, data, integrations, and user workflows.

Whenever you improve either version, identify and implement the corresponding improvements in the other version wherever applicable. This includes UI/UX improvements, layouts, colors, typography, icons, images, navigation, feature behavior, validation, and bug fixes.

Keep native iOS code and platform-specific interactions in the native app. Implement their appropriate equivalents on the website using web technologies. Do not force identical implementations where the platforms require different approaches.

Never overwrite, delete, replace, or simplify existing functionality without understanding its impact. Do not consider a task complete until both versions have been reviewed, relevant changes have been synchronized, and regression tests have been performed wherever possible.

Maintain one shared record of features, design standards, outstanding changes, and known bugs within the existing project documentation. Update it as work progresses instead of creating conflicting instructions or duplicate systems.

If a change cannot safely be applied to both versions, explain why and document the difference. Never silently skip synchronization, claim tests passed without running them, or leave a known regression unresolved.

The priority is one consistent product, two appropriate platform implementations, zero intentional feature loss, and the strongest practical protection against bugs.

### 11:43 AM: UNIFIED PRODUCT: PRACTICAL RULES

1. Access check first: Tell me whether you can see both the website code and the iOS app code. If you can only access one, say so before doing anything, and do not guess what the other version does.

2. Single source of truth for data: Both versions must use the same backend, database, and accounts. Confirm that a user who signs up on one can log in on the other and sees the same profile, articles, and map. Flag any place where the two versions store or handle data differently.

3. Parity table: Create one file in the project (for example PRODUCT_STATUS.md) listing every feature with three columns: works on website, works on iOS, and notes. Update it with every change. Show me the gaps in plain English.

4. Order of work: Where the website and iOS app differ, do not automatically copy one onto the other. Tell me which version is more complete or better, and let me decide before overwriting anything.

5. Release safety: Never push website changes to the live production site without telling me first. The website is live to real users, so test changes in a staging or preview environment where possible.

How we apply them: nothing is copied from one version onto the other without Cheskel's yes. Website pushes to main
(which is live and also updates the Capacitor app) and AI-server republishes are announced to Cheskel first and tested
on a preview first. Pushes to the iOS repo reach users only through a TestFlight build.

---

## 2. Access check (Oct 23, ~15:50 UTC)

| Code | Can read? | How |
|---|---|---|
| Website (private kosher-travel-app, main) | YES, all of it | GitHub API through the connected GitHub account. The local git dir has no remote (`git fetch` fails), but local commit d992194 has exactly the same tree as remote 00f22c1, and the only later commit (5943342) changes only chat-api/_worker.js, which is byte-identical to the AI server source on disk. |
| Capacitor native shell (native-app branch, ios/, android/, capacitor.config.ts) | YES (tree listed via API) | native-app d9cca16 = main + ios/, android/, capacitor.config.ts, docs/native-app.md, a few src/scripts changes. Not read line by line in this pass. |
| Native iOS (public kosher-travel-ios, ios-feature/shell) | YES, all of it | Downloaded the exact head 295cd7b. Note: the shared local working copy is NOT the head; it holds other workers' unpushed edits (DeepLinks, Planner, follow lists). Always read the remote head for status. |
| AI server | YES | its source file (same bytes as chat-api/_worker.js in the website repo) |

---

## 3. Design standards (both versions)

- Colour: navy #191e3b and white. Navy scale #f3f4f9 … #10132a. Body text slate-700/800 or navy; secondary slate-500.
- Red only for: delete, remove, leave, errors (#b4232a / red-600 on web, Color.alert on native) and the liked heart (#ED4956), plus the notification badge. Every delete/remove/leave is red AND asks first.
- No orange, yellow or off-brand colours (web remaps Tailwind amber/orange/yellow to the navy scale).
- Type: Lora serif for screen/section titles and place names on cards; Plus Jakarta Sans for everything else (web). Native: Font.serifTitle() for the same titles, system font elsewhere.
- Icons: outline only (lucide on web, SF Symbols on native), one stroke weight (1.75; 2 for 12-14px). No emoji anywhere in the UI.
- Tap targets at least 44pt. Inputs at least 16px (iOS never zooms).
- Minimal, Instagram-like: white cards, hairlines (#e8edf3), no heavy shadows. Radii: buttons 12, photo cards 16-24, chips full.
- Photos: real photos only, hosted on kosher-travel-img.sites.tab.bot. Never women or girls, churches, crosses, Star of David, nightlife/bars, immodest content, or Israel.
- Content: nothing about Israel; no churches/houses of worship, nightlife, casinos; traveler content is labelled ("Added by a traveler", "Travelers' own words, not checked by the app"); Google results are labelled "From Google (not checked by the app)"; a place found on Google is never shown as kosher.
- Light mode only. Reduce Motion is not handled yet (listed below).
Source: the design-system notes measured Oct 23.

---

## 4. Feature table

| Feature | Works on website (and Capacitor app) | Works on iOS (native or embedded web) | Notes |
|---|---|---|---|
| Sign in: Google, email | Yes | Yes, native | Same Firebase project kosher-travel-app. |
| Sign in with Apple | **No** (no Apple button in the website code) | Yes, native | See gap G1. |
| Username at sign-up (unique) | Yes, new accounts since Oct 23 11:00 UTC (onboarding claims usernames/{name}) | Yes, native (UsernameGate). Also asks existing accounts once, with Skip | Same usernames collection and key rule. Deleting an account frees the name on both. |
| Profile photo, display name | Yes | Yes, native | users/{uid} + profiles/{uid} on both. |
| Profile bio | Capacitor app only (per Oct 23 onboarding note; not re-read) | Missing | |
| Followers / Following lists | **Missing** | Yes, native (Profile, with Follow back) | Gap G4. |
| Following feed | "Following" toggle chip on the Articles feed | Row of round faces of people you follow (build 172; smaller row next build) | Gap G4. |
| Follow button (posts, articles, traveler page) | Yes | Yes, native | users/{uid}/following + followers on both. |
| Explore home (regions, Get Inspired row, What's New, Your upcoming trips) | Yes | Yes, native | |
| Home search | Yes | Embedded web | |
| United States page, Caribbean page (with in-page search) | Yes | Yes, native | |
| State page, country page | Yes | Native (switched on for users at 0b3c3f4 / build 203) | Native data is a bundled copy of the website's lists (see data check D5). |
| State "Kosher Restaurants" view | Exists in code, but the state page does not link to it | Missing | Gap G6. |
| City page (restaurants, grocery, Chabad, shuls/mikvah/eruv, hotels, things to do, tour guides) | Yes | Native (switched on; header matched to the website: Back, Save, Plan Trip over the photo) | 23 of 25 city-audit fixes in. |
| Hotel "Show Radius" map | Opens, but shows only /api/places, which is empty, so effectively blank | Native shows the city's own listings within 1 mile | Gap G5. |
| Place sheet (photos, map, call, website, directions) | Yes | Yes, native | |
| Place reviews | Yes, with Report/Block and banned-user filter | Yes, native, same placeReviews docs. **No Report/Block on place reviews** (park reviews have it); no banned-user filter | Gap G9. |
| State and national parks, park sheets | Yes | Yes, native | |
| Park trail map | Draws trailheads on a circle and generated winding lines (invented routes) | Real park location on Apple Maps, trail list and details, no invented lines (switch kept off) | Gap G3. |
| Things to Do per city/state | Yes | Yes, native (website's own list, 457 of 458 cities) | |
| Places added by travelers ("Added by a traveler · In N stories") | Yes | Yes, native (SharedSights + traveler index, 295cd7b, next build) | |
| "From travelers" link on app listings a post named | Yes | Yes, native (295cd7b, next build) | |
| Tips from travelers | Yes: city, state, country pages and the place sheet | Native: state and country pages, place extras (295cd7b, next build). City page: not confirmed in this pass | Gap G7. |
| Add Establishment form | Form exists; **fails** (/api/places answers 404) | Native form exists; **fails** the same way | Gap G10 / bug B2. |
| Zmanim (card, full list, opinions) | Yes | Yes, native | Preferences are kept on the phone/browser on both. |
| Kosher preferences | Yes | Yes, native | Firestore kosherPrefs + local copy on both. |
| Travel times (origin bar, chips) | Yes | Yes, native | Origin kept on the device on both. |
| Open maps in (Apple/Google/Waze) | Yes | Yes, native | Device setting on both. |
| AI Planner chat | Yes | Yes, native | Same server (native calls yourkoshertravel.com/kt-ai, which forwards to kosher-travel-ai). |
| Planner filters re-answer the same question | Yes (server fix, live) | Yes (server fix, live for build 172) | |
| Google fallback ("From Google (not checked by the app)") | Yes (server, live) | Yes (server, live) | Never for kosher food, shuls, Chabad. |
| AI quotes traveler tips | Yes (server) | Yes (server) | Bug B1 (Ely shows a Sedona tip). |
| Planner actions: PDF, Print, Maps, Calendar, Share, Copy | Yes | Yes, native (build 172) | Untested inside the Capacitor app on a real iPhone (PDF/Calendar). |
| Save to My Travel (AI chat becomes a day-by-day route) | Yes, live, two-account test passed | Native button on the branch (5da3621, built clean); expected in build 203 | Same trip document + /api/trip-extract. |
| Add to Bucket List from the AI (clean card) | Yes | Yes, native (5da3621) | Same preferences.bucketItems. |
| My Travel: trips, Today view, bookings, Hotels nearby, bucket list, saved posts | Yes | Embedded web (same code) | |
| Shared trips: Invite friends, Join, members, live notes, Leave/Remove | Yes, live | Works inside My Travel (embedded). **An invite link does not open in the app yet** | Gap G2. |
| Old ?shareItinerary links | Show the real trip (sample text removed) | Open My Travel in the app (DeepLinks) | |
| My Travel Map + share map | Yes | Embedded web | |
| Traveler page | Yes | Yes, native | |
| Get Inspired feed (reels) | Yes | Yes, native (rail higher, one video plays, sound/fit buttons, Report/Block) | |
| Articles, post page, likes, comments, views | Yes | Yes, native | Same storyPosts fields (likes, likesCount, comments). |
| One share button on posts | Yes | Yes, native | |
| Create a post (Article / Inspiration) | Yes | Native chooser, then the website composer embedded full-screen | |
| Edit / delete own posts | Yes | Through the embedded "My posts and reviews" page | |
| Saved posts | Yes | Yes | users/{uid}/savedPosts on both. |
| Report / Block | Yes (posts, comments, reviews) | Yes for posts and comments; missing on place reviews | |
| Notifications bell | Yes (in-app only) | Yes, native | Push to the phone is not set up on either. |
| What's New (news) page | Yes | Embedded web (row on Explore home is native) | |
| Yahrzeit reminders | Yes | Missing natively | |
| Kivrei Tzadikim | Hidden (links only) | Embedded web | Not promoted (Israel content). |
| Europe | Admin only | Embedded web | |
| Admin tools (review queue, reports, inbox) | Yes | Embedded web | |
| Contact, Privacy, Terms, Delete account | Yes | Yes, native | |
| Universal links (tap a yourkoshertravel.com link, the app opens) | n/a | **Not set up** (needs an AASA file on the website) | Part of G2. |

---

## 5. Shared data check (from the code only; nobody was signed in)

Same backend: YES. Both use Firebase project **kosher-travel-app** (website src/firebase.ts; native GoogleService-Info.plist
from the repo secret, plus the REST URLs in StoryFeed/StoryExtra). Same accounts: Firebase Auth, same users.
Same AI server: YES (native → yourkoshertravel.com/kt-ai → kosher-travel-ai.sites.tab.bot; traveler index read directly
from kosher-travel-ai). Same Firestore collections and field names for:

| Data | Path (both) | Same? |
|---|---|---|
| Profile | users/{uid}, profiles/{uid} | Yes |
| Username | usernames/{folded name} with uid | Yes (same key rule) |
| Posts / articles / inspiration | storyPosts (likes, likesCount, comments, views) | Yes |
| Follows | users/{uid}/following, users/{uid}/followers | Yes |
| Saved posts | users/{uid}/savedPosts | Yes |
| Bucket list | users/{uid}/userData/preferences: bucketList, bucketListTimestamps, bucketItems | Yes |
| Kosher / zmanim / notification prefs | users/{uid}/userData/(kosherPrefs, zmanimPrefs, notifPrefs) | Yes |
| Own trips | users/{uid}/trips (native writes the same doc for Save to My Travel) | Yes |
| Shared trips, invites, bookings | sharedTrips, tripInvites, bookings | Website only, but native shows them through the embedded My Travel, so same data |
| Reviews | placeReviews/{placeKey}__{uid} (parks: placeKind "park") | Yes |
| Reports, blocks | reports, storyReports, commentReports, users/{uid}/blocks | Yes |
| Notifications | users/{uid}/notifications | Yes |
| AI chat history | chatConversations | Same collection (not compared field by field) |
| Banned users | bans | Website reads it; native does not |

So a person who signs up on one version and signs in on the other with the same method sees the same profile,
username, articles, likes, follows, saved posts, bucket list, trips and travel map (the map is built from their
articles). Exceptions:

- **D1. Sign in with Apple exists only on iOS.** Someone who signs up on the iPhone with Apple (often "Hide my email")
  has no Apple button on the website, so they cannot get into the same account there. Same account only if they also
  linked Google or email.
- **D2. Saved places (heart in a place sheet) are kept on the device only** on both (browser localStorage
  "saved_place_<name>"; iPhone UserDefaults, same key). They don't follow the person to another phone or to the website.
  (The bucket list does sync; this is the separate place-sheet heart.)
- **D3. Tour guides a user adds** ("local_tour_guides") and **photos a user adds to a card** ("contributed_photos_<name>")
  are kept on that device only, on both versions. Nobody else sees them.
- **D4. Device-only settings on both** (fine, but worth knowing): zmanim place and opinions copy, travel-times origin,
  "Open maps in", the planner's map-place cache, stories already seen.
- **D5. Map and places data:** the website reads its listings from its own code/data files; the native app ships a
  **bundled copy** (explore.json, parks.json, citytodo.json, statepages.json, statesearch.json), generated from the
  website's code. When a listing is added or fixed on the website, iOS shows it only after the copy is re-exported and a
  new build ships. Traveler-added places and tips are live on both (they come from the server). Maps: Google/OSM on the
  website, Apple Maps natively; the same coordinates.
- **D6. Native does not read the bans list**, so content from a banned user can still show natively.
- **D7. Hotel radius map** uses different data (website: /api/places, empty; native: the city's listings).

---

## 6. Gaps in plain English (which version is better; Cheskel decides, nothing is overwritten)

G1. Sign in with Apple is on the iPhone app but not on the website.
   Better: iOS (more ways to sign in). Risk: Apple-only users are locked out of the website.
   Option: add a "Continue with Apple" button on the website (same Firebase account).

G2. Shared-trip invite links don't open the iPhone app.
   Better: website (the link works there). In the app the trip works inside My Travel, but a tapped link opens the website.
   Option: finish the in-app link handling (being written in DeepLinks, not pushed yet) and add the website file that lets yourkoshertravel.com links open the app.

G3. Park trail maps.
   Better: iOS. The website draws made-up trail lines; iOS shows the real park location and the trail list without fake lines.
   Option: remove the invented lines on the website (show location + trail list), or get real trail data for both.

G4. Following.
   Different, each better at one thing. iOS has the faces row and Followers/Following lists; the website only has a "Following" chip on Articles and no lists.
   Option: add the faces row and the two lists to the website, or keep the chip on both.

G5. Hotel radius map.
   Better: iOS (shows real listings within 1 mile). The website's map is empty because its data source is broken.
   Option: make the website use the city's listings like iOS (or fix /api/places, then decide).

G6. State "Kosher Restaurants" view.
   Better: neither really. It exists in the website code but no button reaches it; iOS doesn't have it.
   Option: either add a "Kosher Restaurants" tab on both state pages, or leave it out on both.

G7. Tips from travelers.
   Better: website (city, state, country pages and place sheet). iOS has state, country and place tips in the next build; city page not confirmed.
   Option: confirm the city page on iOS and add it there if missing.

G8. Username at sign-up.
   Nearly the same. Both claim a unique name for new accounts. iOS also asks older accounts once (with Skip); the website doesn't.
   Option: ask older accounts once on the website too, or stop asking them on iOS.

G9. Report/Block on place reviews, and banned users.
   Better: website (Report/Block on all reviews, banned users hidden). iOS has it on posts, comments and park reviews, but not on place reviews, and doesn't hide banned users.
   Option: add Report/Block and the banned filter to iOS place reviews (Apple requires Block).

G10. Add Establishment fails on both (/api/places answers 404). Same on both; neither works.
   Option: route new places to the admin queue (the traveler-places flow already does this) instead of /api/places.

G11. Places data on iOS is a copy. Better: website (always current).
   Option: re-export the copy with every listing change, or later have iOS load the lists from the server.

G12. Saved places, user-added tour guides and card photos stay on one device, on both versions.
   Option: save them to the account (Firestore) on both, the way the bucket list already is.

G13. Smaller iOS-only gaps: Yahrzeit reminders, profile bio, home search and post editing are web pages inside the app, not native.

Ely / Sedona tip and the 404 are bugs, listed below.

---

## 7. Deliberate platform differences (each with its reason)

| Difference | Reason |
|---|---|
| iOS uses Apple Maps; the website uses Google/OSM maps | Platform maps; same places and coordinates. Both offer "Open maps in" Apple/Google/Waze. |
| iOS uses SF Symbols and system controls (swipe back, sheets, haptics); the website uses lucide icons and web sheets | Native interactions stay native (rule). Same outline style. |
| My Travel, Travel Map, home search, What's New page, composer, Kivrei, Europe and admin are the website inside the iOS app | Not yet rebuilt natively; embedding keeps one code path and the same data. |
| iOS has Sign in with Apple | Apple requires it when Google sign-in is offered in an iOS app. (Website equivalent is gap G1, Cheskel's call.) |
| iOS asks existing accounts for a username once | Cheskel's Oct 23 request was made for the app; website onboarding only shows to new accounts. (Gap G8.) |
| iOS ships a bundled copy of the listings | Offline and fast loading; costs a re-export per change (gap G11). |
| Push notifications | Not set up on either (needs FCM/APNs). |

---

## 8. Outstanding changes

In progress / waiting for a build:
- Native: build 203 (triggered 15:30 UTC): city, state and country pages native for users; city header over the photo; Save to My Travel and Bucket List in the planner; smaller faces row; video pause when half off screen; username at sign-up; deleting an account frees the username. Apple processing not confirmed here.
- Native, next build after 203: traveler places, "From travelers" links and tips (295cd7b).
- Native: trip invite links in DeepLinks (in the working copy, not pushed); follow-list edits (being verified).
- Native: Report/Block on place reviews; banned-user filter (on the native to-do list).
- Universal links / AASA file (needs a website file; website push must be cleared with Cheskel first).
- AI Studio: pull GitHub main and republish (many commits behind: trips, Google fallback, UGC, filter fix).

Waiting for Cheskel:
- Decide each gap in section 6 (G1-G13).
- Hotel radius map: which behaviour for both (G5).
- Trail maps: remove invented lines on the website, or keep (G3).
- Older open decisions from the handoff brief: Bahamas "Kosher Restaurants" tab; Caribbean grouping for Mexico/Central America/Bermuda; ~992 US cards without photos; photos for 4 shuls; Google Maps key restriction; Expedia link; notification switches.

Leftovers (from earlier notes): Wyoming "Day 1-5" chips 34px; 9px text on US state cards and city badges; Reduce Motion; old profile photo files not deleted on change; zmanim Shabbos list 1 minute off his app on 4 rows (we match hebcal).

---

## 9. Known bugs

| # | Bug | Where | Status |
|---|---|---|---|
| B1 | The AI's answer about Ely, NV carries an unrelated traveler tip (Satmar Meat, Sedona) | AI server, traveler-tips matching (both versions) | Open |
| B2 | /api/places answers 404, so Add Establishment fails and the website's hotel radius map is empty | Website API (both versions) | Open |
| B3 | Apple-only accounts cannot sign in on the website | Website | Open (G1) |
| B4 | Invite links open the website, not the app | iOS | In progress (G2) |
| B5 | Place reviews have no Report/Block on iOS; banned users not hidden on iOS | iOS | Open (G9) |
| B6 | Every page in the SHARED-TRIPS local test logged "Unexpected token '<'" | Website, local test only (cause not traced) | To check |
| B7 | Builds on ios-feature/shell keep getting cancelled by new pushes; a cancelled log shows 0 errors and proves nothing | iOS CI | Process rule: verify on a throwaway branch |
| B8 | Saved places, user tour guides and card photos are device-only | Both | Open (G12) |
| B9 | iOS listings are a bundled copy and can fall behind the website | iOS | Open (G11) |
| B10 | PDF / Add to Calendar not tested inside the Capacitor app on a real iPhone | Capacitor | To test |

---

## 10. Regression checklist (run on BOTH versions after any change to that feature)

Accounts
- [ ] Sign up with email on one version, sign in on the other: same name, username, photo, posts.
- [ ] Google sign-in on both. Apple sign-in on iOS (and website once added).
- [ ] New account must pick a unique username; a taken name is refused on both; deleting the account frees it.

Explore
- [ ] Home: regions, Get Inspired row, What's New row, Your upcoming trips.
- [ ] US and Caribbean pages: tiles, counts, travel chips, in-page search ("la fortuna" finds La Fortuna).
- [ ] State page: tabs in website order; city cards with heart, GROCERY/CHABAD links; parks; tips; empty states.
- [ ] Country page: tabs with counts, tour guides box, Things to Do, Kosher Restaurants, Chabad.
- [ ] City page: header (Back, Save, Plan Trip), every hub, listing cards, Show Radius, tour guides, reviews; un-save asks first in red.
- [ ] Place sheet: photos, call, website, directions (Open maps in), reviews (write, edit, Report/Block).
- [ ] Parks: park sheets, trail map, park reviews with Report/Block.
- [ ] Traveler places and "From travelers" links open the post; Tips from travelers show with "See all".

AI Planner
- [ ] A first question answers with the app's places.
- [ ] Filter change re-answers the same question for the same place (Cancun + "Hotel with kosher program").
- [ ] "Things to do" then "more activities" in Punta Cana: app places first, then "From Google (not checked by the app)", new places each time.
- [ ] No Google section for kosher food, shuls or Chabad questions.
- [ ] Action bar: PDF, Maps, Calendar, Share, Copy, Save to My Travel (toast + View), Add to Bucket List ("Already in your Bucket List" on repeat).

My Travel and shared trips
- [ ] Saved AI trip shows as a route with hotel card, days, zmanim, Today view.
- [ ] Invite: user B opens the link (on the website and from inside the app), joins, sees live notes and "day done".
- [ ] Bookings: private stays private, shared shows to members; Leave/Remove/Delete are red and ask first.
- [ ] Bucket list cards show photo, city, summary; remove asks first.

Stories
- [ ] Get Inspired: one video plays at a time, sound and fit buttons, rail position, Report/Block, blocked users hidden.
- [ ] Articles feed; Following (chip on web, faces row on iOS); post page likes/comments/share.
- [ ] Create Article and Inspiration; edit and delete own post (delete red + confirm).
- [ ] Follow / unfollow; Followers and Following lists (iOS); bell notification arrives.

Settings and safety
- [ ] Zmanim, kosher preferences, Open maps in, notification switches.
- [ ] Contact, Privacy, Terms, Delete account.
- [ ] Report reasons match on both; banned users hidden on both.

Release safety
- [ ] Website: tested on a preview first; Cheskel told before any push to main or AI-server republish.
- [ ] iOS: exact head verified on a throwaway branch ("** BUILD SUCCEEDED **" and 0 "error:" lines) before [testflight].

## Motion system (iOS native app, Oct 24 2026, Cheskel 9:14-9:15 PM: animation-only pass)

One file holds every animation timing, spring, transition, press effect and haptic in the native app:
`ios-native/KosherTravel/Design/Motion.swift`. Screens use its names (`Motion.fade`, `Motion.expand`, `.buttonStyle(.pressable)`,
`Motion.Haptic.success` ...) and never write their own durations or springs.

| Name | Value | Used for |
|---|---|---|
| `Motion.pressDuration` | 0.12 s | press-down feedback (starts the instant a finger lands) |
| `Motion.quick` | 0.2 s | fades, small state changes |
| `Motion.standard` | 0.3 s | expand/collapse, toasts, map camera, scroll-to |
| `Motion.gentle` | 0.35 s | cards appearing the first time |
| `Motion.pulseInterval` | 1/30 s | redraw rate of the planner's "typing" dots |
| `Motion.fade` | easeOut 0.2 s | chip/heart/photo fade-ins (same with Reduce Motion) |
| `Motion.select` | snappy 0.2 s | selected tab / filter chip / Follow / Save state |
| `Motion.expand` | snappy 0.3 s | show more / reviews / sections, toasts and notes |
| `Motion.move` | spring (response 0.35, damping 0.86) | photo paging, photo zoom, Fill/Fit, "Added to itinerary" |
| `Motion.press` | spring (response 0.22, damping 0.78) | pressed cards and buttons |
| `Motion.content` | easeOut 0.2 s | spinner -> content crossfade (never a wait) |
| `Motion.scroll` | smooth 0.3 s (Reduce Motion: instant jump) | scroll to a section / newest comment |
| `Motion.camera` | easeInOut 0.3 s (Reduce Motion: instant) | map camera moves |
| `Motion.slide(edge)` | move + fade (Reduce Motion: fade only) | toasts, notices, notes |
| `.pressable` / `.pressableLarge` | scale 0.97 / 0.985 + dim to 88% | cards, tiles, big buttons |

Haptics (restrained, never on every tap): `Motion.Haptic.success` only after a real save/send/sign-in/AI answer;
`.error` with a real failure; `.selection` when a tab/filter/rating/photo page changes; `.tap` (light) for like, send, open composer.

Rules: animations never delay an action, block a tap or change navigation (taps fire at once; springs can be interrupted).
System push/pop, swipe-back, sheets and tab switching stay exactly as iOS does them. Reduce Motion: slides, scaling, springs
and scrolling become a short fade or an instant change. No loops, no confetti, no per-row animations in long lists.
The website was not changed for this pass.
