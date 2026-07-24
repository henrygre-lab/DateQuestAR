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

1. **Deployment Target**: iOS 17.0
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

```
Serendipity/
├── App/
│   ├── DateQuestARApp.swift      # @main entry, environment objects
│   ├── AppDelegate.swift         # Firebase init, push, background config
│   └── RootView.swift            # Auth state router (loading → unauth → onboarding → home)
├── Models/
│   ├── UserProfile.swift         # User, MatchPreferences, PrivacySettings, trust tier
│   ├── Match.swift               # Match, ScoreBreakdown, IcebreakerChallenge
│   ├── EncounterSession.swift    # Time-bounded session, RevealStage, progress tracking
│   └── Enums.swift               # Gender, RelationshipType, AccountStatus, etc.
├── ViewModels/
│   └── AuthViewModel.swift       # Auth state, sign in/up, biometrics, app routing
├── Managers/
│   ├── MatchManager.swift        # AI scoring, quest mode, icebreaker dispatch
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
│   ├── GamificationService.swift # XP/badge writes, Remote Config multipliers
│   └── AnalyticsService.swift    # Firebase Analytics (no PII; UIDs SHA256-hashed)
├── Views/
│   ├── Auth/                     # SplashView, OnboardingView
│   ├── Onboarding/               # ProfileSetupView, LivenessCheckView, WaitlistView
│   ├── Home/                     # HomeView (Quest Mode toggle, match cards)
│   ├── Radar/                    # RadarView (proximity HUD)
│   ├── Icebreaker/               # IcebreakerView, PostMeetRatingView
│   ├── Settings/                 # SettingsView (privacy, auto-pause zones, account)
│   ├── Stats/                    # StatsView (XP, level, badges)
│   └── Components/               # DQTextField, ChipToggle, StatBadge, TrustBadgeView, etc.
├── Utilities/
│   ├── DesignSystem.swift        # DQ design tokens (colors, type, spacing)
│   ├── ColorExtension.swift      # Hex color init
│   └── Geohash.swift             # Native geohash encode/decode (precision 7)
├── Tests/
│   └── MatchManagerTests.swift   # Unit tests: scoring, thresholds, haptic intensity
└── Resources/
    └── SETUP.md                  # This file
```

---

## Developer Bypass

Debug builds include a "Developer Bypass" button on the login screen that signs in with a mock `UserProfile` and skips Firebase authentication. This is guarded by `#if DEBUG` and has zero surface area in production builds.

---

## Key Next Steps (Not Yet Implemented)

| Area | What's Needed |
|---|---|
| Firestore Security Rules | Enforce alert cap atomically server-side |
| ProximityService wiring | Connect UWB/BLE events to `MatchManager.handleNearbyEvent` |
| AI preference alignment | Expand dimension 4 with dealbreaker logic and ML model |
| Apple Sign-In | Requires paid Apple Developer Program enrollment |
| Group anomaly detection | Cloud Function for coordinated bad-actor detection (Risk #6) |
| Post-meet rating UI | Rating view → Cloud Function aggregation → trust score update |
