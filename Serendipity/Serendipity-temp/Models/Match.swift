import Foundation
import CoreLocation

// MARK: - Match

struct Match: Identifiable, Codable, Equatable {
    var id: String
    var userAUID: String
    var userBUID: String
    var compatibilityScore: Double      // 0.0–1.0
    var scoreBreakdown: ScoreBreakdown
    var status: MatchStatus
    var createdAt: Date
    var meetupOccurred: Bool
    var postMeetRating: Int?            // 1–5; refines AI
    var photoAccuracyRatingA: Int?      // 1–5; userA rates userB's photo accuracy
    var photoAccuracyRatingB: Int?      // 1–5; userB rates userA's photo accuracy

    enum MatchStatus: String, Codable {
        case pending                    // Waiting for proximity
        case inProximity               // <0.25 miles — alert sent
        case revealed                  // <0.1 miles — photos shown
        case icebreakerActive          // AR mini-game triggered
        case connected                 // NameDrop exchanged
        case expired
        case reported
    }
}

struct ScoreBreakdown: Codable, Equatable {
    var interestOverlap: Double
    var relationshipTypeMatch: Double
    var ageCompatibility: Double
    var preferenceAlignment: Double

    var overall: Double {
        (interestOverlap + relationshipTypeMatch + ageCompatibility + preferenceAlignment) / 4.0
    }
}

// MARK: - Proximity Event

struct ProximityEvent {
    var matchID: String
    var partnerUID: String
    var distanceMiles: Double
    var hapticIntensity: Float          // 0.0–1.0, ramps with closeness
    var shouldRevealPhotos: Bool        // true when < 0.1 miles
    var timestamp: Date
}

// MARK: - Icebreaker

struct IcebreakerChallenge: Identifiable, Codable {
    var id: String
    var type: ChallengeType
    var prompt: String
    var options: [String]?              // For trivia
    var correctAnswer: String?
    var durationSeconds: Int

    enum ChallengeType: String, Codable {
        case trivia
        case gesture
        case arObject                   // Place same AR object
        case wordAssociation
    }
}
