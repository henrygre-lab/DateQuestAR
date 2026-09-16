// MARK: - SECURITY CHECKLIST COMPLIANCE (see docs/SECURITY_CHECKLIST.md)
// [x] No hardcoded secrets, API keys, or tokens
// [x] Minimal data exposure — intents are a closed enum, not free text
// [x] Fail-closed decode — an unknown raw value decodes to .hangout, never .dating
// [x] Gender-balance tools are scoped to .dating only (usesGenderBalanceTools);
//     Study / Hangout / Event / Friendship overlaps never apply gender caps
// [x] Dating requires ID ↔ liveness face match — see UserProfile.canUseDatingIntent
// [x] The Dating-off cooldown is server-written (datingCooldownUntil); this file
//     only reads it, so toggling Dating off on-device cannot shed caps

import Foundation

// MARK: - Intent

/// What a user is on the app *for*. Serendipity is not a dating app: Dating is
/// one optional intent among five, it is off by default, and it is the only one
/// that engages the gender-balance machinery.
enum Intent: String, Codable, CaseIterable, Identifiable, Sendable {
    case hangout
    case study
    case friendship
    case event
    case dating

    var id: String { rawValue }

    /// The two intents a new user starts with. Home defaults to these.
    static let defaults: [Intent] = [.hangout, .study]

    /// Fail-closed decode: an unrecognised backend value becomes `.hangout`.
    /// Deliberately never `.dating` — a malformed document must not opt someone
    /// into the intent with the strictest verification requirements.
    init(from decoder: Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        self = Intent(rawValue: raw) ?? .hangout
    }

    var displayName: String {
        switch self {
        case .hangout:    return "Hangout"
        case .study:      return "Study"
        case .friendship: return "Friendship"
        case .event:      return "Event"
        case .dating:     return "Dating"
        }
    }

    var subtitle: String {
        switch self {
        case .hangout:    return "Grab coffee, kill an hour between classes"
        case .study:      return "Find someone in the same class or the same library"
        case .friendship: return "Meet people, no other agenda"
        case .event:      return "Going to the same thing tonight"
        case .dating:     return "Optional. Requires student ID face match."
        }
    }

    var systemImage: String {
        switch self {
        case .hangout:    return "cup.and.saucer"
        case .study:      return "book"
        case .friendship: return "person.2"
        case .event:      return "ticket"
        case .dating:     return "heart"
        }
    }

    /// Dating alone engages asymmetric caps, women-first queuing and the male
    /// waitlist. Every other intent matches without gender-based throttling.
    var usesGenderBalanceTools: Bool {
        self == .dating
    }

    /// Dating alone requires the student ID ↔ liveness face match. The other
    /// intents require the school gate + student ID verification (Quest Mode),
    /// which is already stricter than Fizz.
    var requiresFaceMatch: Bool {
        self == .dating
    }

    /// Dating is restricted to verified adults. Incoming students may be 17, and
    /// `enrollmentStatus == .incoming` alone is not evidence of adulthood.
    var requiresVerifiedAdult: Bool {
        self == .dating
    }
}

// MARK: - Intent Overlap

extension Intent {
    /// The intents two users share, in a stable display order.
    ///
    /// This is the value an `EncounterSession` locks at start. Once locked, a
    /// mid-session intent change on either side does not alter the session —
    /// that is what stops a user dropping Dating to shed caps mid-encounter.
    static func overlap(_ a: [Intent], _ b: [Intent]) -> [Intent] {
        let shared = Set(a).intersection(Set(b))
        return Intent.allCases.filter { shared.contains($0) }
    }

    /// Whether a set of locked intents engages the gender-balance tools.
    ///
    /// Note this reads the *locked* overlap, not either user's current intents.
    /// A Study-only overlap never applies gender caps, however either user later
    /// changes their own intent list.
    static func engagesGenderBalance(_ locked: [Intent]) -> Bool {
        locked.contains { $0.usesGenderBalanceTools }
    }
}
