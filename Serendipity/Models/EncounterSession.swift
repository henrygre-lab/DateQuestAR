// MARK: - SECURITY CHECKLIST COMPLIANCE (see SECURITY_CHECKLIST.md)
// [x] No hardcoded secrets, API keys, or tokens
// [x] Session data is Firestore-backed; client state is advisory only
// [x] No raw photo URLs stored — reveal gated by RevealStage enum
// [x] Server timestamps used for startTimestamp, sessionTimeout, lastUpdated
// [x] No PII in logs — only session/match IDs logged
// [x] revealProgress clamped to 0.0–1.0 to prevent invalid state
// [x] Addresses Risk #3 (Swarm / Stratification) from POTENTIAL_ISSUES.md
// [x] Session persistence (10–15 min) handles edge cases from
//     EDGE_CASES_AND_OBJECTIONS.md (bus/train, skyscraper vertical density)

import Foundation
import FirebaseFirestore

// MARK: - Reveal Stage

/// Progressive photo reveal stages. Full photos are only accessible after
/// a completed icebreaker + mutual NameDrop. This directly mitigates
/// Risk #3 (swarm around attractive users) by delaying visual judgment.
enum RevealStage: String, Codable, CaseIterable, Comparable {
    case blurred            // < 0.25 mi — heavily blurred, vibe badges only
    case partial            // Icebreaker active — progressive unblur during AR
    case revealed           // Icebreaker completed — mostly clear + IG tease
    case connected          // Post-NameDrop — full profile access

    private var sortOrder: Int {
        switch self {
        case .blurred:   return 0
        case .partial:   return 1
        case .revealed:  return 2
        case .connected: return 3
        }
    }

    static func < (lhs: RevealStage, rhs: RevealStage) -> Bool {
        lhs.sortOrder < rhs.sortOrder
    }
}

// MARK: - Encounter Session

/// A time-bounded session between two matched users that tracks progressive
/// photo reveal and icebreaker state. Sessions persist 10–15 minutes even
/// if users drift apart, supporting edge cases like bus/train movement and
/// vertical density in skyscrapers.
struct EncounterSession: Identifiable, Codable {
    @DocumentID var id: String?
    var matchID: String
    var userAUID: String
    var userBUID: String
    var startTimestamp: Timestamp
    var revealProgress: Double              // 0.0 (fully blurred) to 1.0 (fully revealed)
    var icebreakerType: IcebreakerChallenge.ChallengeType
    var revealStage: RevealStage
    var sessionTimeout: Timestamp           // startTimestamp + 10–15 min
    var lastUpdated: Timestamp              // Server timestamp on every write

    // MARK: - Session Duration

    /// Default session duration in seconds (10 minutes).
    static let defaultDurationSeconds: TimeInterval = 10 * 60

    /// Maximum session duration in seconds (15 minutes).
    static let maxDurationSeconds: TimeInterval = 15 * 60

    // MARK: - Helpers

    /// Returns true if the session has not timed out.
    func isActive() -> Bool {
        return Date() < sessionTimeout.dateValue()
    }

    /// Returns true if the icebreaker is still in progress (not yet revealed or connected).
    func isIcebreakerInProgress() -> Bool {
        return revealStage == .partial && isActive()
    }

    /// Returns the next reveal stage, or nil if already at .connected.
    func nextStage() -> RevealStage? {
        switch revealStage {
        case .blurred:   return .partial
        case .partial:   return .revealed
        case .revealed:  return .connected
        case .connected: return nil
        }
    }

    /// Returns true if reveal progress warrants advancing to the next stage.
    /// Thresholds: partial at 0.3, revealed at 0.7, connected at 1.0.
    func shouldAdvanceStage() -> Bool {
        switch revealStage {
        case .blurred:   return revealProgress >= 0.3
        case .partial:   return revealProgress >= 0.7
        case .revealed:  return revealProgress >= 1.0
        case .connected: return false
        }
    }

    /// Returns a clamped version of the given progress value (0.0–1.0).
    static func clampProgress(_ value: Double) -> Double {
        return min(max(value, 0.0), 1.0)
    }
}
