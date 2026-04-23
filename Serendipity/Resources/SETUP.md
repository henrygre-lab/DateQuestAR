# DateQuest AR — Project Setup Guide

## Required Info.plist Keys

Add these to your Info.plist for permissions:

```xml
<!-- Location -->
<key>NSLocationAlwaysAndWhenInUseUsageDescription</key>
<string>DateQuest AR needs your location in the background to detect nearby matches during Quest Mode.</string>

<key>NSLocationWhenInUseUsageDescription</key>
<string>DateQuest AR uses your location to find compatible matches nearby.</string>

<!-- Camera (AR + ID verification) -->
<key>NSCameraUsageDescription</key>
<string>Camera is used for AR features, ID verification selfies, and profile photos.</string>

<!-- Photo Library -->
<key>NSPhotoLibraryUsageDescription</key>
<string>Choose photos for your DateQuest AR profile.</string>

<!-- Bluetooth (proximity detection) -->
<key>NSBluetoothAlwaysUsageDescription</key>
<string>Bluetooth is used for precise close-range match detection.</string>

<!-- Face ID -->
<key>NSFaceIDUsageDescription</key>
<string>Use Face ID to quickly and securely access DateQuest AR.</string>

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

Add these in Xcode → File → Add Packages:

| Package | URL | Purpose |
|---|---|---|
| Firebase iOS SDK | https://github.com/firebase/firebase-ios-sdk | Auth, Firestore, Storage |
| GeoFire for iOS | https://github.com/firebase/geofire-objc | Geohash proximity queries |

### Firebase Products to Enable:
- FirebaseAuth
- FirebaseFirestore
- FirebaseStorage
- FirebaseMessaging (push)

---

## Xcode Project Configuration

1. **Deployment Target**: iOS 17.0
2. **Capabilities to Enable** (Signing & Capabilities tab):
   - Background Modes (Location, BLE, Push)
   - Push Notifications
   - Near Field Communication (for NameDrop context)
   - App Tracking Transparency
3. **Entitlements**:
   - `com.apple.developer.nearby-interaction` — UWB NearbyInteraction
   - `com.apple.developer.usernotifications.time-sensitive` — Time-sensitive alerts

---

## Firebase Setup

1. Create a project at https://console.firebase.google.com
2. Add an iOS app with your bundle ID
3. Download `GoogleService-Info.plist` and add it to the Xcode project root
4. Enable **Authentication** → Email/Password, Sign in with Apple, Google
5. Enable **Firestore** in production mode with these security rules:

```
rules_version = '2';
service cloud.firestore {
  match /databases/{database}/documents {
    match /users/{uid} {
      allow read: if request.auth != null;
      allow write: if request.auth.uid == uid;
    }
    match /matches/{matchId} {
      allow read, write: if request.auth != null &&
        (resource.data.userAUID == request.auth.uid ||
         resource.data.userBUID == request.auth.uid);
    }
    match /reports/{reportId} {
      allow create: if request.auth != null;
      allow read: if false; // Admin only
    }
  }
}
```

---

## Architecture Overview

```
DateQuestAR/
├── App/
│   ├── DateQuestARApp.swift      # @main entry, environment objects
│   ├── AppDelegate.swift         # Firebase, push, background config
│   └── RootView.swift            # Auth state router
├── Models/
│   ├── UserProfile.swift         # User, preferences, privacy, badges
│   └── Match.swift               # Match, proximity event, icebreaker
├── ViewModels/
│   └── AuthViewModel.swift       # Auth state, sign in/up, biometrics
├── Managers/
│   ├── MatchManager.swift        # AI scoring, quest mode, proximity
│   └── SafetyVerifier.swift      # ID/selfie verification, reporting
├── Services/
│   ├── FirestoreService.swift    # All Firebase read/write ops
│   ├── LocationService.swift     # Background location, geohash, haptics
│   └── ProximityService.swift    # UWB + BLE close-range detection
├── Views/
│   ├── Auth/
│   │   ├── SplashView.swift
│   │   └── OnboardingView.swift  # Sign in / sign up
│   ├── Onboarding/
│   │   └── ProfileSetupView.swift # Multi-step: verify, photos, bio, prefs, privacy
│   ├── Home/
│   │   └── HomeView.swift        # Dashboard + Quest Mode toggle
│   ├── Radar/
│   │   └── RadarView.swift       # ARKit overlay + haptic proximity HUD
│   ├── Icebreaker/
│   │   └── IcebreakerView.swift  # AR mini-game, trivia, NameDrop
│   └── Settings/
│       └── SettingsView.swift    # Privacy, auto-pause zones, account
├── Utilities/
│   └── ColorExtension.swift      # Hex color init
└── Tests/
    └── MatchManagerTests.swift   # Unit tests: scoring, thresholds, haptics
```

---

## Key TODOs for Production

- [ ] Implement GeoFire geohash range queries in `FirestoreService.fetchNearbyUsers`
- [ ] Integrate real ID verification API (Onfido, Persona, or Stripe Identity)
- [ ] Build ML model trained on post-meet ratings to refine compatibility scoring
- [ ] Implement Sign in with Apple + Google OAuth flows
- [ ] Add AR directional hint nodes in `ARCoordinator.renderer(_:nodeFor:)`
- [ ] UWB token exchange over BLE for precise NearbyInteraction sessions
- [ ] Community events / quests backend (Firestore `events` collection)
- [ ] Rate limiting and abuse prevention on match alerts
- [ ] Instagram API integration for profile enrichment (optional)
- [ ] Google Maps SDK integration for quest location discovery
