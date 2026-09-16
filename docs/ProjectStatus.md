# Serendipity — Project Status (September 16, 2026)

## Build Status
- [x] Clean build succeeds against the iOS 26.5 SDK (re-verified September 16,
      iPhone 17 Pro simulator, exit 0)
- [x] All Firebase modules resolved (Firebase 12.12.1)
- [x] Info.plist + Signing + @main entry point correct
- [x] AlertCapManager, BalanceEnforcer, and core safety features compile
- [x] Cloud Functions typecheck clean (`tsc --noEmit`)
- [ ] Not run on device or simulator since the UI rework — see below
- [ ] **Unit tests cannot be run from a clean checkout** — see below

Two warnings survive the build. The first is deliberate: `OpenURLOptionsKey` is
deprecated in iOS 26, and migrating off it means moving URL handling into a scene
delegate on the auth-critical Google Sign-In path. The call site carries a comment
saying so.

The second is not deliberate and is new since August:
`Services/DemoProximityProvider.swift:57` captures `self` in concurrently-executing
code inside the timer closure. It is a warning today and **an error under the
Swift 6 language mode**, so it will block that migration. It arrived with
`c9f4097` and sits on the `#if DEBUG` demo path, which is why nothing caught it.

### The test suite does not run without Firebase credentials

The XCTest host is the app itself. `AppDelegate.configureFirebase()` skips
`FirebaseApp.configure()` when no `GoogleService-Info.plist` is bundled — but
every `.shared` manager builds a Firestore handle eagerly
(`MatchManager.shared → AlertCapManager.shared → FirestoreService.shared`), so
the app aborts in `+[FIRFirestore firestore]` before the runner connects.

`Resources/SETUP.md` documents this, so it is a known setup requirement rather
than a defect. The consequence is worth stating plainly anyway: **the 76 unit
tests in `SerendipityTests.swift` cannot be executed from a fresh clone, and
cannot run in CI, until the test host can boot against the emulator.** Any claim
that they pass is a claim about a developer machine with real credentials on it.
That is now a prerequisite for step 0 rather than a separate chore.

## Latest: Liquid Glass + logging (August 5)

**Liquid Glass.** The app deploys to iOS 26.2, so the frosted surfaces the spec
described in CSS terms are now the platform material. Adopted on chrome that
floats above content — the tab bar, icon buttons, over-photo chips, the
over-photo reveal meter, the chat composer, and the HUD controls over the AR and
liveness camera feeds — and deliberately kept off the content layer. Full
before/after table in [`UI_REWORK_STATUS.md`](UI_REWORK_STATUS.md) §0; the rule
and its consequences are now spec, in `DESIGN_SYSTEM.md` §5 and §8.

**Logging.** 55 `print` calls across 14 files moved onto `os.Logger` via
`Utilities/Log.swift`. `print` is not compiled out of release builds, and those
calls between them carried a user's geohash, a match's display name and a
reported user's uid — which is the security checklist's §01 rule ("remove all
`print` statements that expose internals in production builds") going unenforced
on the exact data the product exists to protect. Messages are now marked
`.private`, so they read under Xcode and redact everywhere else.

## Security checklist audit (August 5)

Full pass over `docs/SECURITY_CHECKLIST.md` §01–§05. Eight findings, all fixed
except the two noted as still open.

| § | Finding | Status |
|---|---|---|
| 02 | `signIn` assigned Firebase's `localizedDescription` straight to the UI, which distinguishes `.userNotFound` from `.wrongPassword` — an account-enumeration oracle on the login form. The file's own compliance block claimed the opposite | **Fixed** — one message for both |
| 02 | `SafetyVerifier.reportUser` and the verification `catch` rendered raw backend error text; `deleteAccount` and `signOut` did the same | **Fixed** — generic copy, detail to the log |
| 04 | The AR session was never explicitly paused or torn down. ARKit interrupts itself on background, so no camera was left open, but nothing stopped the session when the radar was dismissed and the rule was satisfied only by inheritance | **Fixed** — explicit pause/resume + `dismantleUIView` |
| 01 | Dependencies had never been audited: 20 advisories, 2 critical, 3 high | **Fixed** for critical/high; 9 moderate remained as of this audit, all requiring major bumps of `firebase-admin` and `firebase-functions`. Re-checked September 16: still no critical/high, but **12 moderate** now |
| 03/05 | `grantXP` documented its clamp as "server-side". It runs on the client, in a client-side transaction anyone can bypass | **Fixed** — comment now says advisory, like `AlertCapManager` |
| 04 | `NSFaceIDUsageDescription` missing while `LocalAuthentication` ships. Would crash the moment Face ID is wired | **Fixed** |
| — | `UIRequiredDeviceCapabilities` was `armv7` — 32-bit ARM, which no iOS 26 device has | **Fixed** → `arm64` |
| — | The checklist claimed every source file carries a compliance block; 25 of 75 did, in two different wordings, and `SafetyVerifier` had two stacked | **Fixed** — one wording, convention documented honestly |

**Still open, and both are structural rather than oversights:**

1. ~~**No Firestore Security Rules.**~~ **Closed (September 2).** See the campus
   pivot below.
2. **Motion and altitude filtering do not exist.** `CMMotionActivityManager` and
   `CMAltimeter` appear in no source file. README stated both as shipped and has
   been corrected; `EDGE_CASES_AND_OBJECTIONS.md` was already honest in calling
   them proposals. Vertical density and vehicle noise are unmitigated.

## Campus pivot (September 2)

The product moved from a city-scale proximity dating app to a **campus-gated,
multi-intent** one. Dating is now one of five intents, off by default, and the
only one carrying the gender-balance machinery.

**What was built**

- **Three gates**, each reading only server-issued fields:
  `canEnterCampusCommunity` (school gate) → `canStartQuestMode` (student ID card
  photo + liveness) → `canUseDatingIntent` (ID ↔ liveness face match + verified
  adult age). `canNameDrop` sits alongside the third.
- **`firestore.rules` + `storage.rules` + `firebase.json` + `firestore.indexes.json`.**
  The single largest open gap from the August audit is closed. The rules carry
  the same-school predicate (evaluated per document, so an unconstrained nearby
  query fails outright), the server-owned field list, the write-only verification
  prefix, and the reveal-stage gate on NameDrop. Authorization travels as Firebase
  Auth custom claims, which a client cannot forge.
- **Cloud Functions**: `schoolGate.ts` (phone + `.edu` magic link / school OAuth /
  enrollment proof; issues `schoolId` and `enrollmentStatus`),
  `studentIdVerification.ts` (server-side face match; deletes the artefacts once
  the outcome is recorded), `intents.ts` (intents + the 24h Dating-off cooldown).
  `balanceMonitor.ts` is now per-school and counts Dating-gated users only.
- **Spring Break Mode**: the one pool that is not a campus. Server-dated windows,
  dual server-confirmed presence, verified students only, 45-minute claim TTL.
- **48 unit tests** covering the three gates, the same-school predicate, the
  intent lock, the cooldown and the fail-closed decoders. (Now 76, after the
  four commits below. They were passing on a machine with Firebase credentials;
  see the Build Status caveat above for why that is not reproducible from a
  clean checkout.)

**What this cost**

- `MatchPreferences.RelationshipType` is gone, replaced by `Intent`.
  `ScoreBreakdown.relationshipTypeMatch` became `intentMatch`.
- `FirestoreService.updateTrustLevel` was removed rather than left to fail:
  `trustLevel` is server-owned and a client write is now denied.
- `VerificationStepView` was deleted — it described a driver's licence or
  passport scan, which is no longer the flow. `StudentIDStepView` replaces it.
- `GamificationService.awardXP(uid:)` and `ReferralManager.processReferralReward`
  write another user's document. The rules now correctly deny that, so those
  paths were broken until they moved server-side. **Closed on September 2** —
  see below.

**What is unproven**

The rules have never been executed. There is no Firebase CLI in this environment,
so no `firebase emulators:exec` and no rules unit tests. Everything above is
reasoned and reviewed, not run. That is still the top item on the list below,
and it has not moved since the pivot landed.

## After the pivot (September 2, same day)

Four commits landed after the pivot documentation was written. Two closed items
this document had listed as open; two added scope.

**Closed**

- **XP and referral rewards moved into Cloud Functions** (`207b21a`) — closes
  step 4 below. Self-service grants go through an `awardXP` callable that takes
  no recipient (it always writes `request.auth.uid`) and no amount (the table is
  server-side), so a grant to someone else is not expressible. Referral and
  waitlist-survivor rewards get no callable at all — `activateWaitlistedUsers`
  already runs on a schedule and already knows who was activated. Two duplicate
  XP tables were deleted along the way. `recordDailyLogin` stays a client-side
  self-write and now carries a TODO saying it is the one grant the server-side
  clamp does not cover.
- **The Spring Break claim now refreshes** (`643a715`) — closes the
  carried-over item below. `LocationService` re-confirms presence every 15
  minutes while Quest Mode is on and the device is still in the fence; each
  refresh is the same round-trip that issued the claim, so it cannot extend
  presence the user no longer has. When it cannot be refreshed, presence is
  released server-side and `springBreakStatus` becomes `.paused`, which Home and
  Radar surface. `SpringBreakStatus` is deliberately a separate type from
  `CommunityScope`: the scope decides who you may see, the status decides what
  the screen says, and the gate does not read it.

**Added**

- **A user may hold at most two active encounter sessions** (`7d6faee`).
  `firestore.rules` cannot count across documents, so client creates on
  `encounter_sessions` are denied outright and `openEncounterSession` does the
  count and the write in one transaction. A slot is occupied only while the
  session is active *and* inside its 10–15 minute window, so a timeout needs no
  write and an abandoned encounter strands nobody at the cap. A session costs a
  slot for both participants. Only the caller's own cap is named in the error —
  telling A that B is mid-encounter is a fact about B's evening that B did not
  choose to share.
- **Campus visiting — the Big Game rule** (`ff3bf78`). A school-verified student
  standing on another allowlisted campus can Quest there, seeing that campus's
  home students and its other confirmed visitors. It reuses the
  destination-presence mechanism rather than inventing a second one: same claim
  shape, same 15-minute refresh, same explicit pause, pointed at a `schools/{id}`
  fence. `CommunityScope` did **not** gain a fourth case — `.campus(schoolId)`
  now means "the pool present on that campus", and `isPresent(onCampus:)` carries
  the two asymmetric branches (home `schoolId`, or a different one plus a live
  `campusPresence` claim).

  Two consequences worth keeping in view. The nearby query became two queries and
  a union, because Firestore has no disjunction across two fields. And only the
  home campus gets a monitored `CLCircularRegion` — iOS caps an app at 20, which
  a national school list would exhaust on its own — so visiting campuses are
  detected by containment on location updates, meaning walking onto another
  campus with the app asleep is noticed on the next update rather than instantly.

> **Documentation note.** These four commits shipped without updating this file
> or the README, which is how the README came to state the cross-campus rule
> wrongly for two weeks on a public repo. Corrected September 16.

## Current phase: DesignSystem v2 UI rework

Replacing the v1 purple/mono token layer with the ember, photo-forward v2 system
from the design handoff. Functionality is unchanged throughout: the reveal
mechanic, stage machine, trust ladder and `#if DEBUG` demo path all behave
exactly as before.

**30 of 45 view files are now on v2; 15 still read `enum DQ`.** The three new
campus surfaces (`SchoolGateView`, `StudentIDStepView`, `StudentIDPendingView`)
were written on v2.

**Wave 2 — forms, auth & system chrome (newest):** a second handoff drop added a
form vocabulary to the spec, plus Radar and Settings mocks. `DQFormParts` (1,005
lines, 20 components) implements it: rows, groups, fields, text areas, toggles,
steppers, sliders, segmented pickers, top bars, step dots, empty states,
skeletons, danger rows, confirm sheets and a blocking-save overlay. Migrated on
top of it: `SettingsView`, `AddPauseZoneView`, `ReportUserView`,
`DataRightsView`, and `ProfileSetupView` + all 7 step views. The v1 `DQTextField`
was deleted — `DQFormParts` supersedes it with an identical init signature, so no
call site changed. Five of the nine open design calls are now answered by the
spec; three remain (Radar, camera overlay, OAuth brand marks).

**Wave 1 — the 6 handoff surfaces:**
- `EncounterView` — stepper, RevealHero, score card, rating + tier upgrade, CTA ladder
- `IcebreakerView` — partner strip, trivia rows, word chain, feedback banner
- `HomeView` — QuestCard, DemoControl, nearby signals, floating tab bar
- `TrustCenterView` — current tier, metallic ladder, per-tier requirements, disclaimer
- `SafetySheetView` — two working rows, report-only `danger`; wired to the encounter shield
- `ConnectedChatView` — built but **unreachable**: there is no messaging model

**Not yet migrated (17 files):** `RadarView`, `StatsView`, the auth/liveness tree
(`SplashView`, `OnboardingView`, `LivenessCheckView`, `WaitlistView`),
`NameDropInstructionView`, `PostMeetRatingView`, `RootView` (one token), and the
eight v1 components.

**Blocked on features, not styling:** messaging (no `Message` model, so chat is
unwired and stage 4 still reads "Done"), live-location sharing and check-in
scheduling (both safety rows ship visibly unavailable), and a quest content
model. `TrustCenterView` is now reachable — the Settings row points at it, and
the tier copy describes the campus gate rather than a generic identity ladder.

Fonts are bundled and verified: Plus Jakarta Sans + IBM Plex Mono, SIL OFL 1.1,
in `Resources/Fonts` via a new synchronized group.

Full detail — including everything deferred and why — is in
[`UI_REWORK_STATUS.md`](UI_REWORK_STATUS.md).

## Immediate next steps

0. **Execute the security rules.** They are the enforcement boundary for the
   entire campus gate and they have never run. Install the Firebase CLI, add
   `@firebase/rules-unit-testing` cases for the campus-presence predicate (home
   *and* visiting branches), the server-owned-field rejections and the
   cross-school Spring Break path, and put them in CI. Until this happens the
   gate is reviewed, not verified. **This has been item 0 since September 2 and
   has not moved.** The campus-visiting commit widened what the rules have to get
   right without adding a single executed test, so the gap is larger now than
   when it was written.
1. **Make the test host bootable without real credentials**, then run the 76
   tests. This is a hard prerequisite for putting anything in CI, including
   step 0 — the suite currently cannot run on any machine that lacks a
   `GoogleService-Info.plist`. Either check in an emulator config, or make the
   eager `FirestoreService.shared` construction lazy so the app can launch
   un-configured.
2. **Run it.** Nothing has been exercised at runtime: the floating tab bar's
   safe-area handling, the QuestCard sweep timing, the width-scaled thumbnail
   blur, the step dots, the blocking-save overlay — and the glass, which is the
   kind of change that can only be judged on a device. See
   `UI_REWORK_STATUS.md` §6 for the specific things to look at.
3. Migrate the 15 remaining `enum DQ` readers, then delete it. Three design calls
   need answering first — Radar, the camera overlay (now half-answered: controls
   take glass, the prompt text is still unruled), and OAuth brand marks; see
   `UI_REWORK_STATUS.md` §7. Read the `RadarScreenV2` mock into spec §6 before
   touching `RadarView`.
4. Add mock fixtures + SwiftUI previews so v2 surfaces can be iterated without a
   Firebase sign-in.
5. Fix the Swift 6 concurrency warning in `DemoProximityProvider.swift:57` before
   it becomes a migration blocker.
6. Define a quest content model — the QuestCard is specced around one that does
   not exist.
7. Design messaging, then wire `ConnectedChatView` and restore `Say hello`.
8. **Optional: shrink the repo's history.** `functions/node_modules/` is no
   longer tracked (August 5) — it was 8,847 of 8,973 tracked files, kept alive
   only because it predated the `.gitignore` rule. Untracking stops the growth
   but leaves the old blobs in past commits, so a fresh clone is still large.
   Actually shrinking it means a history rewrite (`git filter-repo`), which is
   worth doing only if clone size becomes a real problem — it invalidates every
   existing clone and rewrites every commit hash.

## Carried over (unchanged from Phase 1/2)

- Firestore Security Rules are written and cover alert-adjacent server-owned
  fields; client caps remain advisory by design, with the rules as the boundary.
  Unexecuted — see step 0.
- ~~The Spring Break `sbDest` claim has a 45-minute TTL that nothing
  re-confirms.~~ **Closed September 2** (`643a715`) — the same 15-minute refresh
  now covers both the destination and campus-visiting claims.
- `ProximityService` UWB/BLE events not yet wired into
  `MatchManager.handleNearbyEvent`.
- Motion and altitude filtering still do not exist — no `CMMotionActivityManager`,
  no `CMAltimeter`. Vertical density and vehicle noise remain unmitigated, and
  both are stated as *proposals* in `EDGE_CASES_AND_OBJECTIONS.md`.
- Coordinated bad-actor / group anomaly detection is still a `SafetyVerifier`
  stub. `LAUNCH_STRATEGY.md` names it a non-negotiable before any marketing push.
- AI preference alignment (dimension 4) still a distance-tolerance check.
- Apple Sign-In stubbed pending paid Developer Program enrollment.
