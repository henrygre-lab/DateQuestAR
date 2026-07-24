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

    // MARK: - Delayed Reveal (Risk #3 mitigation)
    // Full photos are gated behind icebreaker completion + NameDrop.
    // RevealStage controls what photo variant the client may display.
    var revealStage: RevealStage = .blurred
    var encounterSessionID: String?     // Links to active EncounterSession document

    enum MatchStatus: String, Codable {
        case pending                    // Waiting for proximity
        case inProximity               // <0.25 miles — alert sent, photos blurred
        case revealed                  // Icebreaker completed — mostly clear
        case icebreakerActive          // AR mini-game triggered, progressive unblur
        case connected                 // NameDrop exchanged — full profile access
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

