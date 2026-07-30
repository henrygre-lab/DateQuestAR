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
4. Enable **Authentication** → Email/Password + Google
5. Enable **Firestore** with the following baseline security rules:

```
rules_version = '2';
service cloud.firestore {
  match /databases/{database}/documents {
    match /users/{uid} {
      allow read: if request.auth != null;
      // Client may only update alert-tracking fields — all other fields are server-authoritative
      allow write: if request.auth.uid == uid;
    }
    match /matches/{matchId} {
      allow read, write: if request.auth != null &&
        (resource.data.userAUID == request.auth.uid ||
         resource.data.userBUID == request.auth.uid);
    }
    match /encounter_sessions/{sessionId} {
      allow read, write: if request.auth != null &&
        (resource.data.userAUID == request.auth.uid ||
         resource.data.userBUID == request.auth.uid);
    }
    match /reports/{reportId} {
      allow create: if request.auth != null;
      allow read: if false; // Admin SDK only
    }
    match /global_gender_stats/{doc} {
      allow read: if request.auth != null;
      allow write: if false; // Cloud Function only (balanceMonitor)
    }
  }
}
```

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
│   └── RootView.swift            # Auth state router (loading → unauth → onboarding → home)
├── Models/
│   ├── UserProfile.swift         # User, MatchPreferences, PrivacySettings, trust tier
│   ├── Match.swift               # Match, ScoreBreakdown, MatchStatus
│   ├── IcebreakerChallenge.swift # Challenge types, prompts, options
│   ├── EncounterSession.swift    # Time-bounded session, RevealStage, progress tracking
│   ├── GamificationProfile.swift # XP, level, login streak
│   ├── ProximityEvent.swift      # Proximity event payloads
│   ├── FirestoreTypes.swift      # Firestore-facing type shims
│   ├── AppError.swift            # Typed app errors
│   └── Enums.swift               # Gender, RelationshipType, AccountStatus, etc.
├── ViewModels/
│   └── AuthViewModel.swift       # Auth state, sign in/up, biometrics, app routing
├── Managers/
│   ├── MatchManager.swift        # AI scoring, quest mode, icebreaker dispatch, DEBUG demo path
│   ├── AlertCapManager.swift     # Asymmetric daily alert caps (advisory; Firestore rules authoritative)
│   ├── BalanceEnforcer.swift     # Real-time gender ratio gate + women-first queuing
│   ├── RevealManager.swift       # EncounterSession state transitions, photo reveal
│   ├── LivenessDetector.swift    # Vision-based liveness check during onboarding
│   ├── SafetyVerifier.swift      # Group anomaly detection, reporting, account flags
│   ├── XPManager.swift           # XP grants, level progression
│   └── ReferralManager.swift     # Referral code validation + reward multipliers
├── Services/
│   ├── FirestoreService.swift    # All Firestore CRUD, atomic transactions
│   ├── LocationService.swift     # Background location, geohash encoding, haptics
│   ├── ProximityService.swift    # NearbyInteraction (UWB) + CoreBluetooth (BLE)
│   ├── DemoProximityProvider.swift # In-memory walk-up simulation (DEBUG demo)
│   ├── GamificationService.swift # XP/badge writes, Remote Config multipliers
│   └── AnalyticsService.swift    # Firebase Analytics (no PII; UIDs SHA256-hashed)
├── Views/
│   ├── Auth/                     # SplashView, OnboardingView                     [v1]
│   ├── Onboarding/               # ProfileSetupView + steps, LivenessCheck, Waitlist [v1]
│   ├── Home/                     # HomeView — QuestCard, DemoControl, signals     [v2]
│   ├── Encounter/                # EncounterView — the reveal ladder (#if DEBUG)  [v2]
│   ├── Icebreaker/               # IcebreakerView [v2]; NameDrop, PostMeetRating  [v1]
│   ├── Radar/                    # RadarView, ARViewContainer                     [v1]
│   ├── Settings/                 # SettingsView, pause zones, data rights, report [v1]
│   ├── Stats/                    # StatsView                                      [v1]
│   └── Components/
│       ├── DQEncounterParts.swift  # [v2] buttons, chips, meters, radar, safety line
│       ├── DQIcebreakerParts.swift # [v2] partner strip, option rows, chain pills
│       ├── DQHomeParts.swift       # [v2] QuestCard, DemoControl, SignalCard, tab bar
│       ├── RevealHero.swift        # [v2] the progressive-reveal photo
│       ├── StageStepper.swift      # [v2] 4-segment reveal ladder
│       ├── VibeScoreBreakdown.swift/TierUpgradeBanner.swift  # [v2]
│       └── …                       # [v1] DQTextField, ChipToggle, StatBadge, TrustBadgeView, etc.
├── Utilities/
│   ├── DQDesignSystem.swift      # [v2] DQ tokens — read via @Environment(\.dq)
│   ├── DesignSystem.swift        # [v1] legacy `enum DQ` tokens — do not mix with v2
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
| DesignSystem v2 migration | 3 of 6 surfaces migrated; `RadarView`, Settings, Stats and Onboarding still v1 |
| Connected chat / Trust centre / Safety sheet | Designed in the handoff bundle, not built |
| Firestore Security Rules | Enforce alert cap atomically server-side |
| ProximityService wiring | Connect UWB/BLE events to `MatchManager.handleNearbyEvent` |
| AI preference alignment | Expand dimension 4 with dealbreaker logic and ML model |
| Apple Sign-In | Requires paid Apple Developer Program enrollment |
| Group anomaly detection | Cloud Function for coordinated bad-actor detection (Risk #6) |
| Post-meet rating UI | Rating view → Cloud Function aggregation → trust score update |
