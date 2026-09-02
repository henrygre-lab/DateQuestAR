// MARK: - SECURITY CHECKLIST COMPLIANCE (see docs/SECURITY_CHECKLIST.md)
// [x] No hardcoded secrets, API keys, or tokens
// [x] Community context is recorded on the match document (schoolId / campusId /
//     scope / lockedIntents) so the community gate is auditable after the fact
//     rather than only asserted at query time
// [x] campusId is immutable once written (firestore.rules), so a match formed
//     while visiting cannot be relabelled onto another campus later
// [x] Client-written match fields are advisory — firestore.rules re-check that
//     both participants share a schoolId, or that a live Spring Break window
//     covers the match, before allowing the write
// [x] No photo URLs on this type — reveal is gated by RevealStage
// [x] No student ID image, phone number or school email on this type
// [x] Fail-closed decode — an unknown scope raw value decodes to .campus, the
//     narrower pool, never to the cross-school Spring Break pool

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

    // MARK: - Community Context (same-school gate)

    /// The school both users belong to. On a campus match this is their shared
    /// `schoolId`. Inside a Spring Break destination the two users may attend
    /// different schools, so this holds the *viewer's* school and
    /// `partnerSchoolId` holds the other side's.
    var schoolId: String

    /// The partner's school. Equal to `schoolId` for every campus match; differs
    /// only inside a live Spring Break window.
    var partnerSchoolId: String

    /// Which pool produced this match. A `.springBreak` match is only legal
    /// while its destination's server-dated window is live.
    var scope: MatchScope

    /// Destination that authorised a cross-school match, nil for campus matches.
    var springBreakDestinationID: String?

    /// The campus this match was formed on.
    ///
    /// Equal to `schoolId` for the ordinary same-school case. Under the Big Game
    /// rule it is whichever campus the two of them were standing on, which may be
    /// neither person's own — a Stanford student and a Cal student meeting at
    /// Berkeley both record `campusId` "cal". Nil on a Spring Break match, where
    /// `springBreakDestinationID` plays the same role.
    var campusId: String?

    // MARK: - Intent Lock

    /// The intent overlap captured when the encounter opened. Locked for the life
    /// of the match: a mid-session intent change on either side does not alter it.
    var lockedIntents: [Intent] = []

    /// True when both users were Dating-gated (Dating on, or inside the 24h
    /// Dating-off cooldown) at session start. This — not either user's current
    /// intent list — decides whether asymmetric caps, women-first queuing and the
    /// male waitlist apply to this match.
    var isDatingGated: Bool = false

    // MARK: - Delayed Reveal (Risk #3 mitigation)
    // Full photos are gated behind icebreaker completion + NameDrop.
    // RevealStage controls what photo variant the client may display.
    var revealStage: RevealStage = .blurred
    var encounterSessionID: String?     // Links to active EncounterSession document

    /// True when the two participants attend different schools — only reachable
    /// through a live Spring Break window. Drives the school badge on the card.
    var isCrossSchool: Bool {
        schoolId != partnerSchoolId
    }

    enum MatchStatus: String, Codable {
        case pending                    // Waiting for proximity
        case inProximity               // <0.25 miles — alert sent, photos blurred
        case revealed                  // Icebreaker completed — mostly clear
        case icebreakerActive          // AR mini-game triggered, progressive unblur
        case connected                 // NameDrop exchanged — full profile access
        case expired
        case reported
    }

    /// Which community pool a match came out of.
    enum MatchScope: String, Codable {
        case campus
        case springBreak

        /// Fail-closed decode: an unknown value becomes `.campus`, which carries
        /// the same-school requirement. Never `.springBreak`, which relaxes it.
        init(from decoder: Decoder) throws {
            let raw = try decoder.singleValueContainer().decode(String.self)
            self = MatchScope(rawValue: raw) ?? .campus
        }
    }
}

struct ScoreBreakdown: Codable, Equatable {
    var interestOverlap: Double
    var intentMatch: Double
    var ageCompatibility: Double
    var preferenceAlignment: Double

    var overall: Double {
        (interestOverlap + intentMatch + ageCompatibility + preferenceAlignment) / 4.0
    }
}
