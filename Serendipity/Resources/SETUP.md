# Serendipity — Project Setup Guide

## Required Info.plist Keys

```xml
<!-- Location (Quest Mode requires Always authorization) -->
<key>NSLocationAlwaysAndWhenInUseUsageDescription</key>
<string>Serendipity needs background location to detect nearby matches during Quest Mode.</string>

<key>NSLocationWhenInUseUsageDescription</key>
<string>Serendipity uses your location to find compatible matches nearby.</string>

<!-- Camera (AR icebreakers + liveness check + profile photos) -->
<key>NSCameraUsageDescription</key>
<string>Camera is used for AR icebreakers, liveness verification, and profile photos.</string>

<!-- Photo Library -->
<key>NSPhotoLibraryUsageDescription</key>
<string>Choose photos for your Serendipity profile.</string>

<!-- Bluetooth (BLE proximity detection fallback) -->
<key>NSBluetoothAlwaysUsageDescription</key>
<string>Bluetooth is used for close-range match detection when UWB is unavailable.</string>

<!-- Face ID -->
<key>NSFaceIDUsageDescription</key>
<string>Use Face ID to quickly and securely access Serendipity.</string>

<!-- Background Modes -->
<key>UIBackgroundModes</key>
<array>
    <string>location</string>
    <string>bluetooth-central</string>
    <string>bluetooth-peripheral</string>
    <string>remote-notification</string>
</array>

<!-- Bundled fonts (DesignSystem v2). Files live in Resources/Fonts.
     PostScript names are mapped in DQFont — IBM Plex Mono's are irregular. -->
<key>UIAppFonts</key>
<array>
    <string>PlusJakartaSans-Regular.ttf</string>
    <string>PlusJakartaSans-Medium.ttf</string>
    <string>PlusJakartaSans-SemiBold.ttf</string>
    <string>PlusJakartaSans-Bold.ttf</string>
    <string>PlusJakartaSans-ExtraBold.ttf</string>
    <string>IBMPlexMono-Regular.ttf</string>
    <string>IBMPlexMono-Medium.ttf</string>
</array>
```

---

## Swift Package Manager Dependencies

Add in Xcode → File → Add Package Dependencies:

| Package | URL | Purpose |
|---|---|---|
| Firebase iOS SDK | https://github.com/firebase/firebase-ios-sdk | Auth, Firestore |
| Google Sign-In | https://github.com/google/GoogleSignIn-iOS | OAuth |

**Firebase products to enable:** `FirebaseAuth`, `FirebaseFirestore`, `FirebaseFunctions`, `FirebaseAnalytics`

---

## Xcode Project Configuration

0. **Xcode 26+** — the deployment target is iOS 26.2 and the UI uses the Liquid Glass APIs
1. **Deployment Target**: iOS 26.2 (`IPHONEOS_DEPLOYMENT_TARGET` in the project)
2. **Capabilities** (Signing & Capabilities tab):
   - Background Modes (Location Updates, Uses Bluetooth LE Accessories, Remote Notifications)
   - Push Notifications
   - App Tracking Transparency
3. **Required Entitlement**: `com.apple.developer.nearby-interaction` — UWB NearbyInteraction

---

## Firebase Setup

1. Create a project at https://console.firebase.google.com
2. Add an iOS app with your bundle ID
3. Download `GoogleService-Info.plist` and add it to the Xcode project root (gitignored — do not commit)
4. Enable **Authentication** → **Phone**, **Email link (passwordless)**, and **Google**.
   Phone plus an allowlisted `.edu` email link is the school gate; Google (and
   Microsoft, via OIDC) covers the school-tenant OAuth path.
5. Enable **Firestore**, **Storage** and **Cloud Functions**.
6. Deploy the security rules. **They are not optional** — they are the enforcement
   boundary for the campus gate, and without them the same-school rule is a
   client-side courtesy filter:

   ```bash
   firebase deploy --only firestore:rules,firestore:indexes,storage
   ```

   The rules live at the repo root, not in this file: [`firestore.rules`](../../firestore.rules)
   and [`storage.rules`](../../storage.rules), configured by
   [`firebase.json`](../../firebase.json). An earlier version of this document
   inlined a "baseline" ruleset; it has been removed rather than updated, because
   a second copy of security rules in a setup guide is a copy that will drift.

7. Set the function secrets:

   ```bash
   firebase functions:secrets:set MAIL_PROVIDER_API_KEY   # .edu magic link delivery
   firebase functions:secrets:set PHONE_HASH_SALT         # salts the stored phone hash
   firebase functions:secrets:set FACE_MATCH_API_KEY      # student ID <-> liveness match
   firebase functions:secrets:set PERSONA_API_KEY         # optional extra document check
   firebase functions:secrets:set PERSONA_TEMPLATE_ID
   ```

8. Deploy the functions:

   ```bash
   firebase deploy --only functions
   ```

9. **Seed at least one school.** The app is campus-gated: with no `schools`
   document, the gate can issue nothing and no account can reach Quest Mode.
   Create `schools/{schoolId}` with:

   | Field | Type | Notes |
   |---|---|---|
   | `displayName` | string | e.g. `"UCLA"`. The one place name the UI may render |
   | `fullName` | string | e.g. `"University of California, Los Angeles"` |
   | `allowlistedEmailDomains` | string[] | e.g. `["ucla.edu", "g.ucla.edu"]` |
   | `oauthTenantHints` | string[] | Hosted-domain hints; the server re-checks the token |
   | `campus.centerGeohash` | string | Precision 7. Decoded only to arm a region — never rendered |
   | `campus.radiusMeters` | number | **Review this on a map.** Oversized fences import the surrounding neighbourhood |
   | `isActive` | bool | `false` parks the whole community |

10. **Optional — a Spring Break destination.** Create
    `spring_break_destinations/{id}` with `displayLabel`, `centerGeohash`,
    `radiusMeters`, `windowStart`, `windowEnd`, `isActive`, `duskLocalHour` and
    `duskRadiusMiles`. Inside a live window this opens the cross-school pool for
    verified students confirmed at that destination. `isActive: false` is a kill
    switch independent of the dates.

11. **Backfill existing users** (only if you have pre-campus data):
    `firebase functions:call migrateUserProfiles`. It sets community fields to
    their least-privileged values — it does **not** hand anyone a campus. Every
    pre-existing account goes back through the school gate.

> **Running the tests.** The XCTest host is the app itself, and `AppDelegate`
> needs a `GoogleService-Info.plist` in the bundle to launch. Without one the
> test runner crashes before it connects, and every test fails for that reason
> alone. Supply your own config, or point the app at the Firebase emulator suite
> (`firebase emulators:start`).

---

## Project Structure

The app target uses **file-system synchronized groups** (Xcode 16+): App, Models,
ViewModels, Managers, Services, Views, Utilities and Resources/Fonts. Files added
to those folders on disk join the target automatically — no `.pbxproj` edit. Any
*other* new top-level folder must be added as a synchronized group explicitly, or
nothing in it will compile.

```
Serendipity/
├── App/
│   ├── DateQuestARApp.swift      # @main entry, environment objects
│   ├── AppDelegate.swift         # Firebase init, push, background config
│   └── RootView.swift            # Auth state router (loading → unauth → schoolGate
│                                 #   → enrollmentReview → studentIDPending →
│                                 #   onboarding → waitlisted → home)
├── Models/
│   ├── UserProfile.swift         # User, MatchPreferences, PrivacySettings, trust tier,
│                                 #   and the three access gates
│   ├── Intent.swift              # Hangout/Study/Friendship/Event/Dating + overlap rules
│   ├── School.swift              # School, CampusGeofence, SpringBreakDestination,
│                                 #   CommunityScope, CommunityGate (the same-school rule)
│   ├── Match.swift               # Match, ScoreBreakdown, MatchStatus
│   ├── IcebreakerChallenge.swift # Challenge types, prompts, options
│   ├── EncounterSession.swift    # Time-bounded session, RevealStage, progress tracking
│   ├── GamificationProfile.swift # XP, level, login streak
│   ├── ProximityEvent.swift      # Proximity event payloads
│   ├── FirestoreTypes.swift      # Waitlist, GenderStats, VerificationRecord
│   ├── AppError.swift            # Typed app errors
│   └── Enums.swift               # Gender, AccountStatus, EnrollmentStatus,
│                                 #   StudentIDStatus, SchoolGateMethod
├── ViewModels/
│   └── AuthViewModel.swift       # Auth state, sign in/up, biometrics, app routing
├── Managers/
│   ├── SchoolGateManager.swift   # Phone + .edu link / OAuth / enrollment proof; Keychain
│   ├── MatchManager.swift        # AI scoring, quest mode, icebreaker dispatch, DEBUG demo path
│   ├── AlertCapManager.swift     # Dating-only daily caps (advisory; Firestore rules authoritative)
│   ├── BalanceEnforcer.swift     # Per-school Dating ratio gate + women-first queuing
│   ├── RevealManager.swift       # EncounterSession state transitions, photo reveal
│   ├── LivenessDetector.swift    # Vision-based liveness check during onboarding
│   ├── SafetyVerifier.swift      # Student ID submission, reporting, account flags
│   ├── XPManager.swift           # XP grants, level progression
│   └── ReferralManager.swift     # Referral code validation + reward multipliers
├── Services/
│   ├── FirestoreService.swift    # All Firestore CRUD, atomic transactions
│   ├── LocationService.swift     # Background location, geohash, campus + Spring Break
│                                 #   geofences, CommunityScope, haptics
│   ├── ProximityService.swift    # NearbyInteraction (UWB) + CoreBluetooth (BLE)
│   ├── DemoProximityProvider.swift # In-memory walk-up simulation (DEBUG demo)
│   ├── GamificationService.swift # XP/badge writes, Remote Config multipliers
│   └── AnalyticsService.swift    # Firebase Analytics (no PII; UIDs SHA256-hashed)
├── Views/
│   ├── Auth/                     # SplashView, OnboardingView [v1]; SchoolGateView [v2]
│   ├── Onboarding/               # ProfileSetupView + steps, StudentIDStepView,
│                                 #   StudentIDPendingView [v2]; LivenessCheck, Waitlist [v1]
│   ├── Home/                     # HomeView — QuestCard, DemoControl, signals     [v2]
│   ├── Encounter/                # EncounterView — the reveal ladder (#if DEBUG)  [v2]
│   ├── Icebreaker/               # IcebreakerView [v2]; NameDrop, PostMeetRating  [v1]
│   ├── Chat/                     # ConnectedChatView — built, not yet reachable   [v2]
│   ├── Trust/                    # TrustCenterView — reachable from Settings       [v2]
│   ├── Safety/                   # SafetySheetView                                [v2]
│   ├── Radar/                    # RadarView, ARViewContainer                     [v1]
│   ├── Settings/                 # SettingsView, pause zones, data rights, report [v2]
│   ├── Stats/                    # StatsView                                      [v1]
│   └── Components/
│       ├── DQEncounterParts.swift  # [v2] buttons, chips, meters, radar, safety line
│       ├── DQIcebreakerParts.swift # [v2] partner strip, option rows, chain pills
│       ├── DQHomeParts.swift       # [v2] QuestCard, DemoControl, SignalCard, tab bar
│       ├── DQFormParts.swift       # [v2] rows, groups, fields, top bars, empty/loading states
│       ├── RevealHero.swift        # [v2] the progressive-reveal photo
│       ├── StageStepper.swift      # [v2] 4-segment reveal ladder
│       ├── VibeScoreBreakdown.swift/TierUpgradeBanner.swift  # [v2]
│       └── …                       # [v1] ChipToggle, DQBackground, DQButtonStyles,
│                                   #      DQCardModifier, FlowLayout, OAuthButton,
│                                   #      StatBadge, TrustBadgeView
├── Utilities/
│   ├── DQDesignSystem.swift      # [v2] DQ tokens + `dqGlass` — read via @Environment(\.dq)
│   ├── DesignSystem.swift        # [v1] legacy `enum DQ` tokens — do not mix with v2
│   ├── Log.swift                 # os.Logger wrapper — use instead of `print`
│   ├── ColorExtension.swift      # Hex color init
│   └── Geohash.swift             # Native geohash encode/decode (precision 7)
├── SerendipityTests/             # Unit tests
├── SerendipityUITests/           # UI tests
├── design/                       # Design handoff bundle (HTML references) — NOT in the target
└── Resources/
    ├── SETUP.md                  # This file
    └── Fonts/                    # Plus Jakarta Sans + IBM Plex Mono (SIL OFL 1.1) + licences
```

> `[v1]` / `[v2]` mark which design-system token layer a view reads. See
> `docs/UI_REWORK_STATUS.md`. **Never mix the two in one view.**

---

## Developer Bypass

Debug builds include a "Developer Bypass" button on the login screen that signs in with a mock `UserProfile` and skips Firebase authentication. This is guarded by `#if DEBUG` and has zero surface area in production builds.

---

## Key Next Steps (Not Yet Implemented)

| Area | What's Needed |
|---|---|
| DesignSystem v2 migration | 27 of 46 view files on v2 — all 6 handoff surfaces plus the Settings and Onboarding trees. 17 files still read `enum DQ`; it cannot be deleted until they all move |
| Trust centre / connected chat entry points | Both are built but unreachable — the Settings Verification row still pushes a placeholder, and chat needs a `Message` model first |
| Firestore Security Rules | Enforce alert cap atomically server-side |
| ProximityService wiring | Connect UWB/BLE events to `MatchManager.handleNearbyEvent` |
| AI preference alignment | Expand dimension 4 with dealbreaker logic and ML model |
| Apple Sign-In | Requires paid Apple Developer Program enrollment |
| Group anomaly detection | Cloud Function for coordinated bad-actor detection (Risk #6) |
| Post-meet rating UI | Rating view → Cloud Function aggregation → trust score update |
