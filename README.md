# Serendipity

**Serendipity is not a dating app.** It is a campus proximity app: it tells you when someone from *your school* is nearby and worth walking over to, and it only reveals who they are as the two of you physically close the distance.

Five intents — **Hangout, Study, Friendship, Event, Dating** — sit side by side. Home defaults to Hangout and Study. Dating is optional, off unless you pick it, and the only one that carries the gender-balance machinery.

Everything runs inside a verified campus geofence. Off campus, Quest Mode pauses. Cross-campus matching does not exist, with exactly one exception: a live, server-dated Spring Break destination, where verified students from any allowlisted school can see each other for the length of the window and no longer.

---

## Key Features

| Feature | Description |
|---|---|
| **School Gate** | Fizz-style entry: phone number, then an allowlisted `.edu` magic link, school Google/Microsoft OAuth, or an admission letter for incoming students. `schoolId` and `enrollmentStatus` are issued by a Cloud Function and written into custom claims — the client never self-promotes. |
| **Student ID + Liveness** | A student ID card photo and a liveness check are required *before* Quest Mode. Deliberately stricter than Fizz: an `.edu` address gets you into the community, not into proximity scanning. |
| **Intents** | Hangout, Study, Friendship, Event, Dating. Dating requires the student ID ↔ liveness face match and a verified adult age; the other four need only the student ID. |
| **Quest Mode** | Background location scanning inside the campus geofence. Haptic feedback ramps in intensity as a compatible match closes distance (0.25 mi → 0.0 mi). Auto-pauses off campus, and inside user-defined zones (home, work, etc.). |
| **Spring Break Mode** | Colleges travel to the same handful of places, so the product follows them. Inside a live, server-dated destination fence, the pool widens to verified students from *any* allowlisted school — UCLA can see Michigan. Locals and unverified tourists cannot appear. When the window closes or you leave the fence, it snaps back to same-school. |
| **Progressive Photo Reveal** | Photos unlock in four stages tied to physical proximity and shared interaction — no upfront visual judgment. |
| **AR Icebreakers** | Four challenge types (Trivia, Gesture, AR Object, Word Association) fire when users are in proximity. Completing one advances the photo reveal. |
| **AI Compatibility Scoring** | 0.0–1.0 score across interest overlap, relationship type, age compatibility, and preference alignment before any alert fires. Default match threshold: **0.80**. |
| **Asymmetric Alert Caps** | Gender-aware daily caps (women: 10, non-binary: 20, men: 40) — applied **only** to Dating-gated encounters. A Study or Hangout match is never gender-throttled. Client-side caps are advisory; `firestore.rules` is the authoritative gate. |
| **Real-Time Gender Balance** | `BalanceEnforcer` listens to a **per-school** ratio document covering Dating-gated users only. When male% exceeds 55% *on that campus*, male Dating visibility is probabilistically throttled. Women-first queuing and the male waitlist are likewise Dating-only. |
| **Trust Tier System** | Bronze (school email verified) → Silver (student ID + liveness) → Gold (student ID matches your selfie) → Platinum (Gold + avg post-meet rating ≥ 4.0). |
| **XP Gamification** | XP and level progression earned for icebreakers completed, NameDrops, and daily logins (`XPManager`). Badge definitions live in `GamificationService`; `GamificationProfile` stores XP, level, and login streak only. |

---

## How It Works

### Stage Progression

```
0. School gate → student ID + liveness
   └── schoolGate.ts issues schoolId + enrollmentStatus (custom claims)
         └── studentIdVerification.ts issues studentIDStatus
               └── .verified opens Quest Mode; .faceMatched opens Dating + NameDrop

1. Quest Mode active, inside the campus geofence
   └── Someone from the SAME school enters the 0.25 mi radius
         └── CommunityGate.canShare → shared intent → (Dating only:
             AlertCapManager + BalanceEnforcer)
               └── Both phones alert (haptics, vibe badges — NO photos yet)

2. Users physically approach
   └── EncounterSession opens (10–15 min, persists even if users briefly drift apart)
         └── AR icebreaker activates
               └── Photo progressively unblurs as challenge progresses (revealProgress 0.0 → 1.0)

3. Icebreaker completed
   └── Photo mostly clear + Instagram teaser visible
         └── Prompt: "Vibe passed? NameDrop to connect."

4. Mutual NameDrop (opt-in, requires the student ID ↔ liveness face match)
   └── Full profile unlocked — official match
         └── Post-meet accuracy rating → feeds into trust score
```

### The three gates

Each reads only server-issued fields, and each is re-checked by `firestore.rules` against Firebase Auth custom claims. Client-side predicates are a courtesy filter.

| Gate | Predicate | Requires | Opens |
|---|---|---|---|
| 1 | `canEnterCampusCommunity` | `schoolId` issued, `enrollmentStatus` ∈ {enrolled, incoming}, account active | Seeing your campus community |
| 2 | `canStartQuestMode` | Gate 1 + student ID card photo and liveness passed | Quest Mode, proximity scanning, nearby |
| 3 | `canUseDatingIntent` | Gate 2 + student ID ↔ liveness face match + verified adult age | The Dating intent |

`canNameDrop` sits alongside gate 3: the face match, but not the age check, because NameDrop is reachable on a Study encounter too.

### Same-school rule, and its single exception

`CommunityScope` is the one place the rule lives:

- **`.campus(schoolId)`** — both parties must belong to *that* school. A Michigan student standing on the UCLA lawn is out of pool.
- **`.springBreak(destinationId, displayLabel)`** — inside a live, server-dated window, and only once the backend has confirmed *both* parties are at that destination. School-verified students only; locals and unverified tourists match no branch.
- **`.none`** — off campus and outside every live fence. Quest Mode pauses; every query returns empty.

Rules cannot see device location, so they cannot verify physical presence. They enforce school membership, verification depth, the server-dated window, and server-confirmed destination presence (via the short-lived `sbDest` claim that `confirmDestinationPresence` issues after re-checking the fence itself). Physical presence is enforced by `LocationService` auto-pause and by that same function. This limitation is stated in the rules file rather than papered over.

### Encounter Session Detail

`EncounterSession` is Firestore-backed and tracks `RevealStage` (`blurred → partial → revealed → connected`) plus a `revealProgress` float (0.0–1.0). Stage thresholds:

- `partial` at progress ≥ 0.30
- `revealed` at progress ≥ 0.70
- `connected` at progress ≥ 1.00 (post-NameDrop only)

> **Not yet implemented.** Earlier drafts of this section described 3D proximity via `CMAltimeter` altitude and a `CMMotionActivityManager` walking/running filter gating session creation. Neither framework is referenced anywhere in the codebase. Both remain *proposed* mitigations in [`docs/EDGE_CASES_AND_OBJECTIONS.md`](docs/EDGE_CASES_AND_OBJECTIONS.md) — vertical density (someone 40 floors up) and vehicle noise (alerts from passing cars) are currently unmitigated.

---

## Architecture

MVVM with `ObservableObject` services. All business logic lives in Managers and Services; Views bind only to `@Published` state. No logic in Views.

```
┌──────────────────────────────────────────────┐
│                  Presentation                │
│   RootView (state router)                    │
│     ├── AuthViewModel ──► FirebaseAuth       │
│     └── HomeView / RadarView / IcebreakerView│
└─────────────────┬────────────────────────────┘
                  │ binds to
┌─────────────────▼────────────────────────────┐
│                  Managers                    │
│   SchoolGateManager ─ phone + .edu / OAuth / │
│                       enrollment proof       │
│   MatchManager   ─── scoring, quest mode,    │
│                       icebreaker dispatch    │
│   AlertCapManager ─── Dating-only daily caps │
│   BalanceEnforcer ─── per-school Dating ratio│
│   RevealManager  ─── EncounterSession state  │
│   LivenessDetector ─ Vision-based liveness   │
│   SafetyVerifier ─── student ID, reports     │
└─────────────────┬────────────────────────────┘
                  │ reads/writes
┌─────────────────▼────────────────────────────┐
│                  Services                    │
│   FirestoreService  ── Firestore CRUD        │
│   LocationService   ── CoreLocation, geohash,│
│                        campus + SB geofences,│
│                        CommunityScope        │
│   ProximityService  ── NearbyInteraction/BLE │
│   GamificationService ─ XP + badges         │
│   AnalyticsService  ── event logging (no PII)│
└─────────────────┬────────────────────────────┘
                  │ gated by
┌─────────────────▼────────────────────────────┐
│         Server (authoritative)               │
│   firestore.rules  ─ same-school predicate,  │
│                      server-owned fields     │
│   storage.rules    ─ write-only verification │
│   schoolGate.ts    ─ issues schoolId         │
│   studentIdVerification.ts ─ issues          │
│                      studentIDStatus         │
│   intents.ts       ─ intents + 24h cooldown  │
│   balanceMonitor.ts ─ per-school Dating ratio│
└──────────────────────────────────────────────┘
```

`Models/School.swift` holds `CommunityScope` and `CommunityGate` — the pairwise same-school predicate every path runs through. `Models/Intent.swift` holds the five intents and the `usesGenderBalanceTools` flag that scopes the caps to Dating.

---

## Tech Stack

| Layer | Technology |
|---|---|
| Language | Swift 5 |
| UI | SwiftUI — dark mode enforced. Two token layers mid-migration: `DQDesignSystem.swift` (v2, current) and `DesignSystem.swift` (v1, legacy). See [Design System](#design-system). |
| Material | Liquid Glass (iOS 26) on chrome that floats above content — tab bar, icon buttons, over-photo chips, camera HUDs. Content surfaces stay opaque. |
| Typography | Plus Jakarta Sans + IBM Plex Mono, bundled (SIL OFL 1.1) |
| Architecture | MVVM + `ObservableObject` services |
| Backend | Firebase Auth + Cloud Firestore |
| Location | CoreLocation, geohash (precision 7, native implementation) |
| Short-range proximity | NearbyInteraction (UWB), CoreBluetooth (BLE) |
| Haptics | CoreHaptics |
| AR | ARKit |
| Computer Vision | Vision framework (liveness detection) |
| Auth | Firebase Auth — phone (school gate), email link (`.edu` magic link), school Google/Microsoft OAuth. Custom claims (`schoolId`, `enrollmentStatus`, `studentIDStatus`, `sbDest`) carry authorization into `firestore.rules`. Face ID via `LocalAuthentication` is implemented but not wired to any screen |
| Secure storage | Keychain (`kSecClassGenericPassword`, `WhenUnlockedThisDeviceOnly`) for the phone number. Nothing sensitive is in `UserDefaults` |
| Security rules | `firestore.rules`, `storage.rules`, `firestore.indexes.json`, `firebase.json` at the repo root |
| Analytics | AppTrackingTransparency-compliant, no PII in events |
| Logging | `os.Logger` via `Utilities/Log.swift`, one category per subsystem area, messages marked `.private` |
| Tests | XCTest (unit + UI) |

---

## Requirements & Setup

**Requirements**
- Xcode 26+ (the deployment target is iOS 26.2 and the UI uses the Liquid Glass APIs; the project also uses file-system synchronized groups, which need Xcode 16+)
- iOS 26.2+ — this is the `IPHONEOS_DEPLOYMENT_TARGET` currently set in the project
- Physical device required — location services, haptics, and NearbyInteraction do not work in Simulator
- "Always On" location permission required for Quest Mode background scanning
- Firebase project with Auth and Firestore enabled

**Setup**
1. Clone the repo and open `Serendipity/Serendipity.xcodeproj`
2. Add your `GoogleService-Info.plist` to the `Serendipity/` target directory
3. Resolve Swift Package dependencies (Firebase SDK) via Xcode → File → Packages
4. Build and run on a physical device

> **Developer Bypass** — Debug builds include a login-screen bypass that signs in with a mock `UserProfile`. Useful for UI work without a live Firebase project.

---

## Safety, Privacy & Trust

These are design constraints, not afterthoughts. Each decision maps to a specific risk in `docs/POTENTIAL_ISSUES.md`.

**Location Privacy**
- Raw coordinates are never stored. All location data is encoded as a precision-7 geohash (~150 m cell) before any Firestore write.
- Three sharing modes: `precise` (opt-in only), `anonymized` (default), `hidden`.
- Configurable geofence auto-pause zones keep Quest Mode off at home and work.
- **Almost no place is ever named in the UI.** Outside an active encounter, the count of nearby signals is the only *spatial* fact displayed — never a neighbourhood, city, venue, building or landmark, and never a geohash or campus polygon. Storing coordinates safely is worth nothing if a screen prints the neighbourhood back out, and ambient screens are the most screenshotted.
  Exactly two strings are exempt, both **community identity** rather than position: the school's own `displayName` ("Quest Mode · UCLA") and, inside a live window, a Spring Break destination's server-supplied `displayLabel` ("Cancún · Spring Break"). Both are identical for everyone in that community, so neither localises the person holding the phone. The test: if a string could differ for two people standing 500 m apart, it is position and it does not ship. Enforced as a design rule in [`docs/DESIGN_SYSTEM.md`](docs/DESIGN_SYSTEM.md) §7/§8.
- **Nothing identifying reaches the device log.** All logging goes through `Utilities/Log.swift`, which hands messages to `os.Logger` marked `.private` — readable when attached to Xcode or Console, redacted in any log a shipping build hands out. This replaced 55 `print` calls, which were not compiled out of release builds and between them carried a user's geohash, a match's display name and a reported user's uid.

**Campus Community**
- Every nearby, match, icebreaker and NameDrop path hard-gates on `schoolId`. There is no cross-campus matching outside a live Spring Break window.
- `firestore.rules` evaluates its read predicate per document on a list query, so a nearby query that reaches beyond the caller's own community **fails as a whole** rather than returning a filtered set. That is what makes the same-school rule enforceable rather than advisory.
- Off campus and outside every live fence, `CommunityScope` is `.none`: Quest Mode pauses, the pool empties, and the Home screen says so rather than showing an empty list.
- Cross-school visibility during Spring Break requires four things at once: a live server-dated window, the viewer server-confirmed at that destination, the subject confirmed at the *same* destination, and both school-verified.

**Identity Verification & Liveness**
- The liveness check is powered by the Vision framework. The camera prompts two randomly selected actions (turn left, turn right, blink, smile) and confirms completion across ≥ 3 consecutive frames.
- **The pass/fail decision is the server's.** `studentIdVerification.ts` runs the face match; the on-device Vision comparison in `SafetyVerifier` is a pre-flight hint so a user can retake a bad photo before spending one of three hourly attempts. It sets no field and gates nothing.
- **Student ID images never appear on a profile, and never in a nearby or match payload.** They are uploaded to `verification/{uid}/`, which `storage.rules` makes create-only for the owner and readable by *nobody* — not even the uploader. Only the Admin SDK reads them, and it deletes both the card and the liveness frames once the outcome is recorded. Only the outcome survives.
- Trust tiers reflect verification depth:
  - **Bronze** — school email verified (the school gate)
  - **Silver** — student ID card photo + liveness check passed
  - **Gold** — student ID matches your selfie (opens Dating and NameDrop)
  - **Platinum** — Gold + average post-meet accuracy rating ≥ 4.0

**Asymmetric Alert Caps — Dating only**
- Women receive significantly fewer inbound *Dating* alerts (10/day) vs. men (40/day). Non-binary: 20/day.
- **These apply only to Dating-gated encounters.** A Study, Hangout, Friendship or Event overlap is never gender-throttled. `AlertCapManager.canSendAlert` requires the session's locked intents as an argument, and there is no overload that lets a caller skip it.
- `AlertCapManager` enforces this client-side as a courtesy gate. `firestore.rules` is the authoritative enforcement layer.
- Caps sync to Firestore using `updateData` on alert-only fields — server-owned fields are never sent by the client, because the rules would reject the whole write.

**The intent-toggle exploit, and how it is closed**

Scoping the caps to Dating creates an obvious dodge: switch Dating off, shed the caps, keep receiving alerts. Four things close it, and all four are needed.

1. **The intent overlap is locked at session start.** `EncounterSession.lockedIntents` and `isDatingGated` are computed once from *both* users and frozen. Changing your intents mid-session does not touch a session in flight.
2. **`activeIntents` is server-owned.** `firestore.rules` refuses a client write to it. Intents change only through the `setActiveIntents` Cloud Function — which is what makes step 3 unavoidable.
3. **Switching Dating off starts a 24-hour server-written cooldown.** During it, `isDatingGated()` stays true, so the caps, women-first queuing and the waitlist keep applying. Switching Dating back on does not clear an existing cooldown, so an on/off/on cycle cannot shorten it.
4. **An alert counts as Dating only if *both* users were Dating-gated at session start.** One person having Dating on cannot gender-throttle someone else's Study match; one person switching it off cannot escape the caps.

`balanceMonitor` counts cooldown users in the ratio for the same reason: without it, a wave of men switching Dating off would drop out of the denominator and make a skewed campus look balanced.

**Gender Balance Enforcement — per school, Dating only**
- `BalanceEnforcer` listens to `global_gender_stats/{schoolId}`, written exclusively by a Cloud Function. **Balance is a campus fact, not a national one:** a 50/50 national split can still be a 90/10 campus, and throttling on the wrong denominator throttles the wrong people.
- The counts cover Dating-gated users only.
- When male percentage exceeds 55% on that campus, male Dating visibility is probabilistically reduced (pass rate scales down linearly from 1.0, floored at 0.10).
- Alert caps are dynamically halved for men during high-imbalance periods.
- Women-first queuing is toggled server-side and read by `BalanceEnforcer`.
- The male waitlist queues someone **for Dating only**, and only when they have actually selected it. Hangout, Study, Friendship and Events keep working while queued, and `WaitlistView` says so.

**Anti-Harassment**
- Per-user ping cap: any single user can receive a maximum of 5 alerts per hour from the same partner.
- 15-minute cooldown between alerts for the same match pair.
- "Unsafe Proximity" one-tap report + group anomaly detection via `SafetyVerifier`.
- `accountStatus` enum gates all match visibility: `active / waitlisted / suspended / banned`.

**Progressive Reveal as Safety Mechanism**
- Photos are never surfaced at first alert. Visual identity only unlocks through mutual AR interaction. This removes the "swarm around attractive users" failure mode and eliminates cold visual rejection at the point of meeting.
- NameDrop — the exchange of real contact details — additionally requires the student ID ↔ liveness face match, whatever the encounter's intent. Three layers enforce it: the view refuses to show the instructions, `RevealManager.completeReveal` refuses to advance the stage, and `firestore.rules` rejects a write moving `revealStage` to `connected` without the `faceMatched` claim. The last one is the one that counts.

**Server-authoritative by construction**

These fields are written only by Cloud Functions, and `firestore.rules` rejects every client write to them: `schoolId`, `schoolDisplayName`, `enrollmentStatus`, `studentIDStatus`, `verifiedAge`, `verificationStatus`, `trustLevel`, `trustScore`, `accountStatus`, `datingCooldownUntil`, `activeIntents`, `springBreakDestinationId`, `balanceBoostMultiplier`, `alertCapPerHour`, `waitlistEntryTime`, `activationDelayHours`.

Authorization reaches the rules through Firebase Auth **custom claims** (`schoolId`, `enrollmentStatus`, `studentIDStatus`, `sbDest`), which are signed into the ID token and cannot be forged by a client. `FirestoreService.saveProfileEdits` writes a field whitelist rather than encoding the whole profile, so a stale client copy of a server-owned field can never fail — or worse, silently pass — a write.

---

## Design System

The UI is mid-migration between two token layers. **New work should target v2.**

| | v1 (legacy) | v2 (current) |
|---|---|---|
| File | `Utilities/DesignSystem.swift` | `Utilities/DQDesignSystem.swift` |
| Entry point | `enum DQ` — `DQ.Colors.accent` | `@Environment(\.dq)`, `DQRadius` / `DQSpace` / `DQSize`, `DQFont` |
| Accent | Purple `#A855F7` | Ember `#F2683C` |
| Theme | Dark only | Dual-theme (currently pinned dark) |

The names are close enough to be a trap: check which system a view already reads and stay in it. Never mix them in one view. Both files carry a header saying so.

**Liquid Glass** is applied through `dqGlass` in the v2 layer, and only to chrome that floats above content: the tab bar, icon buttons, over-photo chips, the over-photo reveal meter, the chat composer, and the HUD controls over the AR and liveness camera feeds. Content — cards, rows, panels, fields, sheets — stays on the opaque `surface` tokens, because glass that covers everything has nothing left to float above. The rule and its consequences (no borders, no drop shadows on small glass chrome) are in [`docs/DESIGN_SYSTEM.md`](docs/DESIGN_SYSTEM.md) §5; what changed where is in [`docs/UI_REWORK_STATUS.md`](docs/UI_REWORK_STATUS.md) §0.

- **The spec** — [`docs/DESIGN_SYSTEM.md`](docs/DESIGN_SYSTEM.md). Source of truth for tokens, components, motion and screen composition. This repo copy is canonical: rulings are written into it by whoever implements them. The spec wins on values.
- **What's actually built** — [`docs/UI_REWORK_STATUS.md`](docs/UI_REWORK_STATUS.md). Migration status, deferred items and why, deliberate departures from the mocks.

**27 of 46 view files are on v2.** All six handoff surfaces (`EncounterView`, `IcebreakerView`, `HomeView`, `TrustCenterView`, `SafetySheetView`, `ConnectedChatView`), the Settings tree (`SettingsView`, `AddPauseZoneView`, `ReportUserView`, `DataRightsView`) and the Onboarding tree (`ProfileSetupView` + all seven step views), plus the components they own.

Component layers live in `Views/Components`: `DQEncounterParts`, `DQIcebreakerParts`, `DQHomeParts` for the encounter flow, and `DQFormParts` for forms, auth and system chrome — rows, groups, fields, toggles, steppers, sliders, segmented pickers, top bars, step dots, empty states, skeletons, confirm sheets and the blocking-save overlay.

Still on v1 — **17 files**: `RootView`, `RadarView`, `StatsView`, `SplashView`, `OnboardingView`, `LivenessCheckView`, `WaitlistView`, `NameDropInstructionView`, `PostMeetRatingView`, and eight v1 components (`ChipToggle`, `DQBackground`, `DQButtonStyles`, `DQCardModifier`, `FlowLayout`, `OAuthButton`, `StatBadge`, `TrustBadgeView`). `enum DQ` cannot be deleted until they all move.

Fonts are bundled in `Serendipity/Resources/Fonts` and registered via `UIAppFonts` — no setup step required.

---

## Known Limitations / Current Scope

These are deliberate next steps, not gaps — the campus gate, the same-school rule and the proximity-reveal-AR loop are implemented end to end.

| Area | Current State | Next Step |
|---|---|---|
| UI rework | 28 of 48 view files on v2 — all 6 handoff surfaces, the Settings and Onboarding trees, and the new `SchoolGateView` / `StudentIDStepView` / `StudentIDPendingView` | Migrate the 17 remaining v1 files, delete `enum DQ`, then drop the theme pin and go `colorScheme`-driven |
| Messaging | `ConnectedChatView` is built but there is **no `Message` model, collection, or send path** | Design messaging; then wire the view and restore the stage-4 `Say hello` CTA |
| Safety actions | *End encounter* and *Report* work; *Share live location* and *Check in later* have no backing feature and ship visibly unavailable | Build a live-location link service and a check-in scheduler |
| Spring Break check-in trigger | `confirmDestinationPresence` and the fence detection are built and wired into `LocationService.reevaluateScope`. The `sbDest` claim has a 45-minute TTL, but **nothing re-confirms it before it lapses** — a user standing at a destination for an hour silently drops back to same-school until the next region crossing | Add a timer that re-confirms presence at half the TTL while the scope is `.springBreak` |
| Live rules verification | `firestore.rules` and `storage.rules` are written but have **never been executed** — no Firebase CLI in this environment, so no `firebase emulators:exec` and no rules unit tests | Install the CLI, add `@firebase/rules-unit-testing` cases for the same-school predicate and the server-owned-field rejections, and run them in CI |
| Cross-user XP writes | `GamificationService.awardXP(uid:)` and `ReferralManager.processReferralReward` write another user's document. `firestore.rules` now correctly denies that — the paths are broken until they move server-side | Move XP grants and referral rewards into Cloud Functions |
| Enrollment proof review | `submitEnrollmentProof` queues a review and `reviewEnrollmentProof` is admin-only, but there is no admin surface to call it from | Build the review tool, or wire it to an existing admin console |
| Quest content model | Quest Mode is a `Bool`; no quest title, description, or `n / m` progress exists | Define a quest model so the QuestCard can carry real quest content |
| Dynamic Type | Neither design system scales with Dynamic Type | Audit both layers and adopt scaled fonts |
| Runtime verification | Builds clean against the iOS 26.5 SDK and the 48 unit tests pass. **No v2 surface has been run**, on device or in Simulator, and the Liquid Glass work has never been looked at. The test host itself needs a `GoogleService-Info.plist` to launch — without one it crashes before the tests connect | Add a checked-in emulator config so the test host boots without real Firebase credentials; add mock fixtures and SwiftUI previews |
| ProximityService wiring | UWB/BLE service implemented; not yet connected to MatchManager trigger path | Wire `ProximityService` events into `MatchManager.handleNearbyEvent` |
| AI preference alignment | Dimension 4 (preference alignment) uses distance-tolerance check only | Expand with dealbreaker logic and ML model |
| Apple Sign-In | Stub implemented | Requires paid Apple Developer Program enrollment |
| Firestore Security Rules | **Closed.** `firestore.rules` and `storage.rules` now carry the same-school predicate, the server-owned field list, the write-only verification prefix and the reveal-stage gate. See *Live rules verification* above for what is still unproven | Move the remaining client-side XP and trust writes behind Cloud Functions |
| Motion / altitude filtering | Not implemented — no `CMMotionActivityManager`, no `CMAltimeter`. Vertical density and vehicle noise are unmitigated | Build the walking/running gate and the altitude check described in `EDGE_CASES_AND_OBJECTIONS.md` |
| Cloud Functions dependencies | `npm audit` clean of critical/high as of 2026-08-05; 9 moderate advisories remain, all needing a major bump of `firebase-admin` (→14) and `firebase-functions` (→7) | Take the majors deliberately, with a deploy to the emulator to catch API breakage |
| AR Icebreaker views | Challenge types defined and dispatched; AR Object + Gesture views in progress | Complete ARKit placement views for all four types |
| Post-meet rating pipeline | Rating flow integrated into trust score recalculation, but the client no longer writes `trustLevel` (it is server-owned), so recalculation is now display-only | Build rating UI and the Cloud Function that actually applies the tier change |
| Vibe filter vs. intents | The 0.6 Jaccard `intentVibes` pre-filter still gates every match, including Study ones. It predates intents and is a second, overlapping notion of "what you're here for" | Decide whether vibes survive intents, and if so scope the threshold per intent |

---

## Competitor Differentiation

The closest comparison is no longer a dating app. It is **Fizz** — a campus-gated social network — and the differences run in both directions.

| App | Their Approach | Serendipity's Difference |
|---|---|---|
| **Fizz** | Campus-gated anonymous feed. Entry is a phone number plus an allowlisted `.edu` address | Same gate, then **stricter**: a student ID card photo and liveness check are required before Quest Mode, and an ID ↔ selfie face match before Dating or NameDrop. Fizz gates a feed; we gate a signal that tells someone where to walk, which is a higher bar |
| Happn | Shows who you crossed paths with — instant photo exposure, retroactive matching, city-wide | Campus-scoped and same-school only. No photo until you've interacted in AR; meeting is the icebreaker, not the outcome |
| Breeze | Scheduled IRL dates | Fully spontaneous; no pre-planning required |
| Swerv | Venue-based map, check-in model | Passive Quest Mode inside a campus geofence — no venue dependency and no check-in |
| Hinge / Tinder | Async swiping catalog, no physical proximity, dating only | Physical co-presence required, and dating is one of five intents rather than the premise. Home defaults to Hangout and Study |

---

## License

Copyright 2026 Serendipity. All rights reserved. Unauthorized reproduction, distribution, or modification is prohibited.
