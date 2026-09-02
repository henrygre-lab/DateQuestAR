// MARK: - SECURITY CHECKLIST COMPLIANCE (see docs/SECURITY_CHECKLIST.md)
// [x] No hardcoded secrets, API keys, or tokens
// [x] All Firestore writes require Firebase Auth UID ownership check
// [x] schoolId, enrollmentStatus, studentIDStatus, verifiedAge, trustLevel,
//     accountStatus, datingCooldownUntil, campusPresenceSchoolId and
//     campusPresenceExpiresAt are server-authoritative — issued by
//     schoolGate.ts / studentIdVerification.ts and rejected on client write by
//     firestore.rules. The client reads them and never self-promotes.
// [x] Visiting-campus presence is a server-issued claim with an expiry, not a
//     self-declared field: a client that could write campusPresenceSchoolId
//     could put itself on any campus in the country
// [x] No student ID image, liveness frame, phone number or school email on this
//     type — those live on users/{uid}/verification/** (owner-only) and are
//     therefore absent from every nearby and match payload built from a profile
// [x] Asymmetric daily alert caps apply ONLY to Dating-gated encounters; the cap
//     value here is advisory and Firestore Security Rules are the real boundary
// [x] Dating-off cannot shed caps — datingCooldownUntil is server-written and
//     isDatingGated() honours it for 24h after Dating is switched off
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

    // MARK: - Campus Community (server-authoritative)

    /// Issued by `schoolGate.ts` after phone + allowlisted .edu magic link,
    /// school OAuth, or approved enrollment proof. Nil until the gate passes.
    /// `firestore.rules` rejects any client write to this field.
    var schoolId: String?

    /// Denormalised community identity for the nearby card badge, e.g. "UCLA".
    /// Written alongside `schoolId` by the same Cloud Function so a nearby card
    /// can render the badge without a second read. Community identity only —
    /// never a neighbourhood, venue or building (DESIGN_SYSTEM.md §8).
    var schoolDisplayName: String?

    /// Server-authoritative. Only `.enrolled` and `.incoming` enter a community.
    var enrollmentStatus: EnrollmentStatus = .unverified

    /// The campus this user has been server-confirmed to be physically standing
    /// on, when it is not their own. Written by `confirmCampusPresence` and
    /// cleared when they leave — the visiting half of the Big Game rule.
    ///
    /// Nil for the overwhelmingly common case of a student on their own campus:
    /// `schoolId` already says where they belong, and a home student needs no
    /// second claim to be visible there.
    var campusPresenceSchoolId: String?

    /// When the visiting claim lapses. Server-written; refreshed every 15 minutes
    /// while the user is still inside the fence.
    var campusPresenceExpiresAt: Timestamp?

    /// Server-authoritative result of the student ID card photo + liveness check.
    /// The images themselves never reach this document.
    var studentIDStatus: StudentIDStatus = .none

    // MARK: - Intents

    /// What this user is on the app for. Dating is optional and off by default —
    /// new profiles start on Hangout + Study.
    var activeIntents: [Intent] = Intent.defaults

    /// Set by the server for 24h when a user switches Dating off. While it is in
    /// the future, Dating-gated protections still apply to this uid.
    ///
    /// This is the intent-toggle exploit fix: dropping Dating removes the user
    /// from the Dating pool but does not remove them from Dating's caps.
    var datingCooldownUntil: Timestamp?

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
    // male-skewed user bases. These apply to Dating-gated encounters only —
    // a Study or Hangout overlap is never gender-throttled. Limits are enforced
    // server-side via Firestore Security Rules; client values are advisory only.

    var alertsSentToday: Int = 0
    var lastAlertResetDate: Date = Date()

    /// Gender-based daily alert cap for **Dating-gated** encounters.
    /// Women receive fewer inbound alerts to prevent overload in
    /// male-heavy populations. Non-binary and prefer-not-to-say
    /// sit between the two extremes.
    ///
    /// Callers must not apply this to a session whose locked intent overlap
    /// excludes Dating — see `AlertCapManager.canSendAlert(for:to:lockedIntents:)`.
    var currentDailyLimit: Int {
        switch gender {
        case .female:         return 10
        case .nonBinary:      return 20
        case .preferNotToSay: return 15
        case .male:           return 40
        }
    }

    /// Formats a date as a "yyyy-MM-dd" day key in **UTC**.
    /// UTC is chosen deliberately: the daily-reset boundary stays stable and
    /// deterministic regardless of the device's timezone (and lines up with
    /// server-side day bucketing). This also makes rollovers testable — callers
    /// can pass a fixed `Date` to force a day change.
    static func dayKey(for date: Date) -> String {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC") ?? .current
        let c = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", c.year ?? 0, c.month ?? 0, c.day ?? 0)
    }

    /// Returns true if the user hasn't hit their daily alert cap.
    /// Automatically resets the counter if the UTC day has rolled over.
    /// Pass `now` to test deterministically.
    mutating func canSendAlert(using now: Date = Date()) -> Bool {
        resetAlertsIfNeeded(using: now)
        return alertsSentToday < currentDailyLimit
    }

    /// Resets `alertsSentToday` to 0 when the UTC calendar day changes.
    /// Compares the day key of `now` against the last reset's day key, so it
    /// only resets on an actual day rollover (timezone-safe, testable).
    mutating func resetAlertsIfNeeded(using now: Date = Date()) {
        if Self.dayKey(for: now) != Self.dayKey(for: lastAlertResetDate) {
            alertsSentToday = 0
            lastAlertResetDate = now
        }
    }

    /// Increments the daily alert counter by 1.
    /// Call only after `canSendAlert()` returns true. Pass `now` to test deterministically.
    mutating func incrementAlertCount(using now: Date = Date()) {
        resetAlertsIfNeeded(using: now)
        alertsSentToday += 1
    }

    // MARK: - Trust Level

    enum TrustLevel: String, Codable, Comparable {
        case bronze     // School gate passed (phone + .edu / OAuth / enrollment proof)
        case silver     // Student ID card photo + liveness check passed
        case gold       // Student ID ↔ liveness face match confirmed
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

// MARK: - Access Gates

/// The three preconditions the whole product hangs off. Each reads only
/// server-authoritative fields, so a client cannot widen its own access by
/// editing local state — and `firestore.rules` re-checks the same predicates.
extension UserProfile {

    /// Verified adult per the student ID. `age` is self-reported and is never
    /// used here; `verifiedAge` is written by `studentIdVerification.ts`.
    var isVerifiedAdult: Bool {
        (verifiedAge ?? 0) >= 18
    }

    /// **Gate 1 — school gate.** May this account see a campus community at all?
    ///
    /// Requires a server-issued `schoolId`, an enrollment status that grants
    /// access (`.enrolled` or `.incoming`), and an account in good standing.
    var canEnterCampusCommunity: Bool {
        guard let schoolId, !schoolId.isEmpty else { return false }
        guard enrollmentStatus.grantsCommunityAccess else { return false }
        guard accountStatus == .active else { return false }
        return true
    }

    /// **Gate 2 — Quest Mode.** Student ID card photo + liveness on top of the
    /// school gate. This is deliberately stricter than Fizz: an .edu address
    /// alone gets you into the community, not into proximity scanning.
    var canStartQuestMode: Bool {
        canEnterCampusCommunity && studentIDStatus.isIDVerified
    }

    /// **Gate 3 — Dating.** Student ID ↔ liveness face match, plus verified
    /// adulthood. `.incoming` students may be 17, and admission proof says
    /// nothing about age, so the face-match age is the one that counts.
    var canUseDatingIntent: Bool {
        canStartQuestMode && studentIDStatus.isFaceMatched && isVerifiedAdult
    }

    /// Whether this user counts as being on campus `schoolId`.
    ///
    /// Two ways to be on a campus, and they are not symmetric:
    ///
    /// - **Home.** Your own `schoolId` matches. No presence claim needed — this
    ///   is how the same-school pool has always worked, and requiring a claim
    ///   would break every student standing on their own quad.
    /// - **Visiting.** A different school, plus a live server-issued presence
    ///   claim on this one. That claim is the entire Big Game rule: it is what
    ///   separates a Stanford student actually at Cal from a Stanford student
    ///   who would quite like to be.
    ///
    /// The visiting branch checks the expiry, so a lapsed claim stops counting
    /// without anyone having to clear it.
    func isPresent(onCampus schoolId: String, at now: Date = Date()) -> Bool {
        guard !schoolId.isEmpty else { return false }
        if self.schoolId == schoolId { return true }
        guard campusPresenceSchoolId == schoolId else { return false }
        guard let expiry = campusPresenceExpiresAt?.dateValue() else { return false }
        return now < expiry
    }

    /// True when this user is on a campus that is not their own.
    func isVisiting(campus schoolId: String, at now: Date = Date()) -> Bool {
        self.schoolId != schoolId && isPresent(onCampus: schoolId, at: now)
    }

    /// NameDrop exchanges real identity, so it carries the Dating-tier proof
    /// even when the encounter's intent is Study or Hangout.
    var canNameDrop: Bool {
        canStartQuestMode && studentIDStatus.isFaceMatched
    }

    // MARK: - Dating State

    /// Dating is currently switched on for this user.
    var isDatingActive: Bool {
        activeIntents.contains(.dating) && canUseDatingIntent
    }

    /// Inside the server-written 24h cooldown that follows switching Dating off.
    func isInDatingCooldown(at now: Date = Date()) -> Bool {
        guard let until = datingCooldownUntil?.dateValue() else { return false }
        return now < until
    }

    /// Dating protections apply to this user right now — either Dating is on, or
    /// they are inside the cooldown that follows switching it off.
    ///
    /// Used when locking an `EncounterSession`'s intents: an alert counts as
    /// Dating only if *both* users are Dating-gated at session start.
    func isDatingGated(at now: Date = Date()) -> Bool {
        isDatingActive || isInDatingCooldown(at: now)
    }

    /// The intents this user can actually offer right now, with Dating filtered
    /// out unless the face-match and adult gates are satisfied. Never trust
    /// `activeIntents` directly for matching.
    var eligibleIntents: [Intent] {
        activeIntents.filter { intent in
            guard intent.requiresFaceMatch || intent.requiresVerifiedAdult else { return true }
            return canUseDatingIntent
        }
    }
}

// MARK: - Match Preferences

struct MatchPreferences: Codable {
    var ageRange: ClosedRange<Int>          // e.g. 22...30
    var maxDistanceMiles: Double            // Quest range; capped at 0.25
    var genderPreferences: [String]
    var interests: [String]                 // e.g. ["hiking", "coffee", "travel"]
    var dealbreakers: [String]
    var compatibilityThreshold: Double      // 0.0–1.0; default 0.80
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
