// MARK: - SECURITY CHECKLIST COMPLIANCE (see docs/SECURITY_CHECKLIST.md)
// [x] No hardcoded secrets, API keys, or tokens
// [x] Session data is Firestore-backed; client state is advisory only
// [x] No raw photo URLs stored — reveal gated by RevealStage enum
// [x] Server timestamps used for startTimestamp, sessionTimeout, lastUpdated
// [x] No PII in logs — only session/match IDs logged
// [x] revealProgress clamped to 0.0–1.0 to prevent invalid state
// [x] Same-school gate recorded on the session (schoolId / partnerSchoolId /
//     scope) so a cross-school session is only representable when a live Spring
//     Break destination authorised it
// [x] Intent overlap is locked at session start — switching Dating off mid-session
//     cannot change this session's gender-balance posture
// [x] isDatingGated is computed from BOTH users at start (Dating on, or inside the
//     server-written 24h Dating-off cooldown); a Study/Hangout-only overlap never
//     engages gender caps
// [x] Encounter slots are server-counted. participantUIDs, slotState,
//     closedReason and closedAt are written only by encounterSessions.ts, and
//     firestore.rules denies client creates outright — a local array of sessions
//     is exactly what a swarming client would edit.
// [x] A session occupies a slot for BOTH participants, so two people cannot be
//     held in more encounters between them than either has room for
// [x] Timeout frees a slot with no write at all: the count query filters on
//     sessionTimeout, so an abandoned session stops occupying a slot on its own
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

    // MARK: - Community Context

    /// School of `userAUID`. Equal to `partnerSchoolId` on every campus session.
    var schoolId: String

    /// School of `userBUID`. Differs only inside a live Spring Break window.
    var partnerSchoolId: String

    /// Which pool opened this session.
    var scope: Match.MatchScope = .campus

    /// Destination that authorised a cross-school session, nil on campus.
    var springBreakDestinationID: String?

    // MARK: - Encounter Slots
    //
    // The scarcity mechanic. Two active encounters per person, because the thing
    // being rationed is attention in the physical world: someone juggling six
    // icebreakers at once is not meeting any of those six people, and on a
    // campus that pattern is the swarm.

    /// Both participants, denormalised so the backend can count a user's active
    /// sessions with a single `array-contains` query. Server-written.
    var participantUIDs: [String] = []

    /// Whether this session still occupies a slot. Server-written.
    var slotState: SlotState = .active

    /// Why the slot was freed. Nil while the session is still running.
    var closedReason: CloseReason?

    var closedAt: Timestamp?

    /// Whether this session is holding a slot right now.
    ///
    /// Two conditions, and the second is why timeout needs no write: a session
    /// past its window stops occupying a slot whether or not anyone closed it.
    /// An abandoned encounter cannot strand a user at the cap.
    func occupiesSlot(at now: Date = Date()) -> Bool {
        slotState == .active && now < sessionTimeout.dateValue()
    }

    /// Whether the slot is still held. Mirrors the backend's count predicate.
    enum SlotState: String, Codable {
        case active
        case closed

        /// Fail-closed decode: an unknown value counts as still occupying a slot.
        /// Erring toward "occupied" costs a user one encounter; erring the other
        /// way lets them hold unlimited ones, which is the thing being prevented.
        init(from decoder: Decoder) throws {
            let raw = try decoder.singleValueContainer().decode(String.self)
            self = SlotState(rawValue: raw) ?? .active
        }
    }

    /// How a session ended. Every case frees the slot; they differ only in what
    /// the analytics and the audit trail record.
    enum CloseReason: String, Codable {
        /// Mutual NameDrop — the encounter succeeded.
        case nameDrop
        /// The user explicitly ended it without exchanging details.
        case pass
        /// "Unsafe Proximity" reported. Terminates immediately.
        case unsafeProximity
        /// The 10–15 minute window elapsed. Recorded for the audit trail; the
        /// slot was already free, because the count filters on the window.
        case timeout
        /// Quest Mode switched off, so the user is no longer meeting anyone.
        case questModeOff

        init(from decoder: Decoder) throws {
            let raw = try decoder.singleValueContainer().decode(String.self)
            self = CloseReason(rawValue: raw) ?? .timeout
        }
    }

    // MARK: - Intent Lock

    /// The intent overlap captured at session start, frozen for the session's
    /// life. Re-reading either user's current intents here would reopen the
    /// toggle exploit, so nothing in the session path does.
    var lockedIntents: [Intent] = []

    /// Whether this session is Dating-gated, decided once at start from both
    /// users' Dating state (active, or inside the 24h Dating-off cooldown).
    var isDatingGated: Bool = false

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

    // MARK: - Slot Cap

    /// How many encounters one person may hold at once.
    ///
    /// Two, not one: a single slot would mean the first person who walks past
    /// locks you out of everyone else for fifteen minutes, which is worse than
    /// the swarm it prevents. Two leaves room to be mid-encounter and still
    /// notice someone, without room to collect people.
    static let maxActiveSessionsPerUser = 2

    /// Counts the sessions in `sessions` that hold a slot for `uid`.
    ///
    /// Client-side courtesy only — `encounterSessions.ts` runs the same count
    /// against Firestore inside a transaction, and that is the one that decides.
    static func activeSlotCount(for uid: String,
                                in sessions: [EncounterSession],
                                at now: Date = Date()) -> Int {
        sessions.filter { $0.participantUIDs.contains(uid) && $0.occupiesSlot(at: now) }.count
    }

    /// Whether `uid` has no room for another encounter.
    static func isAtSlotCap(_ uid: String,
                            in sessions: [EncounterSession],
                            at now: Date = Date()) -> Bool {
        activeSlotCount(for: uid, in: sessions, at: now) >= maxActiveSessionsPerUser
    }

    // MARK: - Intent Locking

    /// The intent overlap to freeze onto a new session between two users.
    ///
    /// Reads `eligibleIntents`, not `activeIntents`, so a user who has Dating
    /// switched on without the face match never contributes Dating to the lock.
    static func lockIntents(_ a: UserProfile, _ b: UserProfile) -> [Intent] {
        Intent.overlap(a.eligibleIntents, b.eligibleIntents)
    }

    /// Whether a session between these two users is Dating-gated.
    ///
    /// Requires *both* sides to be Dating-gated at start — Dating on, or inside
    /// the server-written 24h cooldown that follows switching it off. One user
    /// having Dating on is not enough to gender-throttle a Study overlap, and one
    /// user switching Dating off is not enough to escape the caps.
    static func locksDatingGate(_ a: UserProfile,
                                _ b: UserProfile,
                                at now: Date = Date()) -> Bool {
        a.isDatingGated(at: now) && b.isDatingGated(at: now)
    }

    /// True when the two participants attend different schools — only reachable
    /// through a live Spring Break window.
    var isCrossSchool: Bool {
        schoolId != partnerSchoolId
    }
}
