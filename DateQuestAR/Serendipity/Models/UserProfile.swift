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
    var createdAt: Date
    var lastActive: Date

    enum VerificationStatus: String, Codable {
        case unverified
        case pending
        case verified
        case flagged
    }

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

// MARK: - Gamification

struct GamificationProfile: Codable {
    var level: Int
    var xp: Int
    var badges: [Badge]
    var questsCompleted: Int
    var totalConnections: Int
}

struct Badge: Identifiable, Codable {
    var id: String
    var name: String
    var iconName: String
    var earnedAt: Date
    var description: String
}
