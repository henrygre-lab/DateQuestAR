// MARK: - Vibe Coding Security Checklist Compliance
// [x] No hardcoded secrets, API keys, or tokens
// [x] All Firestore writes require Firebase Auth UID ownership check
// [x] Gender + accountStatus fields are server-validated; client only reads
// [x] alertCapPerHour enforced server-side via Firestore rules, not client trust
// [x] Asymmetric daily alert caps (currentDailyLimit) are advisory client-side;
//     Firestore Security Rules are the real enforcement boundary
// [x] No raw coordinates stored — location uses geohash only
// [x] waitlistEntryTime uses Firestore Timestamp (server clock, not client)
// [x] Minimal PII exposure — intentVibes are user-supplied tags, not free text

import Foundation
import CoreLocation
import FirebaseFirestore

// MARK: - User Profile

struct UserProfile: Identifiable, Codable {
    @DocumentID var id: String?
    var uid: String
    var displayName: String
    var age: Int
    var bio: String
    var photoURLs: [String]         // Ordered; first is primary
    var selfDescriptors: [String]   // e.g. ["adventurous", "bookworm"]
    var verificationStatus: VerificationStatus
    var trustLevel: TrustLevel = .bronze
    var verifiedAge: Int?
    var verificationCompletedAt: Date?
    var preferences: MatchPreferences
    var privacySettings: PrivacySettings
    var gamification: GamificationProfile
    var isProfileComplete: Bool = false
    var trustScore: Double = 0.5
    var createdAt: Date
    var lastActive: Date

    // MARK: - Gender Balance & Safety Fields (Phase 1)

    var gender: Gender = .preferNotToSay
    var alertCapPerHour: Int = 8
    var currentHourAlerts: [String: Int] = [:]   // key = "yyyy-MM-dd-HH"
    var balanceBoostMultiplier: Double = 1.0
    var accountStatus: AccountStatus = .active
    var waitlistEntryTime: Timestamp?
    var activationDelayHours: Int?
    var intentVibes: [String] = []
    var socialContextPreference: Bool = true

    // MARK: - Asymmetric Daily Alert Caps (Mitigation #1)
    // Lower caps for women protect against notification overload from
    // male-skewed user bases. Limits are enforced server-side via
    // Firestore Security Rules; client values are advisory only.

    var alertsSentToday: Int = 0
    var lastAlertResetDate: Date = Date()

    /// Gender-based daily alert cap.
    /// Women receive fewer inbound alerts to prevent overload in
    /// male-heavy populations. Non-binary and prefer-not-to-say
    /// sit between the two extremes.
    var currentDailyLimit: Int {
        switch gender {
        case .female:         return 10
        case .nonBinary:      return 20
        case .preferNotToSay: return 15
        case .male:           return 40
        }
    }

    /// Returns true if the user hasn't hit their daily alert cap.
    /// Automatically resets the counter if the date has rolled over.
    mutating func canSendAlert() -> Bool {
        resetAlertsIfNeeded()
        return alertsSentToday < currentDailyLimit
    }

    /// Resets `alertsSentToday` to 0 when the calendar day changes.
    mutating func resetAlertsIfNeeded() {
        if !Calendar.current.isDateInToday(lastAlertResetDate) {
            alertsSentToday = 0
            lastAlertResetDate = Date()
        }
    }

    /// Increments the daily alert counter by 1.
    /// Call only after `canSendAlert()` returns true.
    mutating func incrementAlertCount() {
        resetAlertsIfNeeded()
        alertsSentToday += 1
    }

    // MARK: - Trust Level

    enum TrustLevel: String, Codable, Comparable {
        case bronze     // Email verified (Firebase Auth complete)
        case silver     // Live selfie liveness check passed
        case gold       // Selfie + ID face match confirmed
        case platinum   // Gold + avg post-meet rating ≥ 4.0 (≥3 ratings)

        private var sortOrder: Int {
            switch self {
            case .bronze: 0
            case .silver: 1
            case .gold: 2
            case .platinum: 3
            }
        }

        static func < (lhs: TrustLevel, rhs: TrustLevel) -> Bool {
            lhs.sortOrder < rhs.sortOrder
        }
    }
}

// MARK: - Match Preferences

struct MatchPreferences: Codable {
    var ageRange: ClosedRange<Int>          // e.g. 22...30
    var maxDistanceMiles: Double            // Quest range; capped at 0.25
    var relationshipTypes: [RelationshipType]
    var genderPreferences: [String]
    var interests: [String]                 // e.g. ["hiking", "coffee", "travel"]
    var dealbreakers: [String]
    var compatibilityThreshold: Double      // 0.0–1.0; default 0.80

    enum RelationshipType: String, Codable, CaseIterable {
        case shortTerm = "Short-Term"
        case longTerm  = "Long-Term"
        case casual    = "Casual"
        case friendship = "Friendship"
    }
}

// MARK: - Privacy Settings

struct PrivacySettings: Codable {
    var questModeEnabled: Bool
    var visibilityRadius: Double            // miles
    var autoPauseZones: [GeoFenceZone]      // home, work, etc.
    var alertLimit: Int                     // max alerts per day
    var locationSharingMode: LocationSharingMode
    var showInCommunityEvents: Bool

    enum LocationSharingMode: String, Codable {
        case precise
        case anonymized     // geohashed; default
        case hidden
    }
}

// MARK: - GeoFence Zone

struct GeoFenceZone: Identifiable, Codable {
    var id: String = UUID().uuidString
    var label: String                       // "Home", "Work", "Gym"
    var geohash: String                     // Anonymized center
    var radiusMeters: Double                // Pause radius
    var isActive: Bool
}

