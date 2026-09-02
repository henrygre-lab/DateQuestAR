// MARK: - SECURITY CHECKLIST COMPLIANCE (see docs/SECURITY_CHECKLIST.md)
// [x] No hardcoded secrets, API keys, or tokens
// [x] Minimal data exposure — enums are value types with no PII
// [x] No client-side trust decisions — enrollmentStatus and studentIDStatus are
//     written only by Cloud Functions (schoolGate.ts, studentIdVerification.ts);
//     firestore.rules reject any client write to those fields
// [x] Codable raw values are safe string literals only
// [x] Decoding is fail-closed — unknown raw values decode to the least-privileged
//     case (.unverified / .none) rather than throwing or granting access

import Foundation

// MARK: - Gender

enum Gender: String, Codable, CaseIterable {
    case male
    case female
    case nonBinary = "non_binary"
    case preferNotToSay = "prefer_not_to_say"
}

// MARK: - Account Status

enum AccountStatus: String, Codable, CaseIterable {
    case active
    case waitlisted
    case suspended
    case banned
}

// MARK: - Verification Status

enum VerificationStatus: String, Codable, CaseIterable {
    case unverified
    case pending
    case verified
    case flagged
}

// MARK: - Enrollment Status

/// Server-authoritative enrollment state, issued by `schoolGate.ts` after the
/// school gate passes. The client never writes this — `firestore.rules` rejects
/// any client-supplied `enrollmentStatus` on the user document.
///
/// Only `.enrolled` and `.incoming` may enter a campus community. `.alumni` is
/// retained deliberately: graduating must revoke community access rather than
/// silently leaving an account in the pool.
enum EnrollmentStatus: String, Codable, CaseIterable {
    case unverified     // School gate not passed — no community access
    case pending        // Enrollment proof submitted, awaiting review
    case incoming       // Admitted, not yet matriculated (proof of enrollment)
    case enrolled       // Currently enrolled and verified
    case alumni         // No longer enrolled — community access revoked
    case revoked        // Access withdrawn (fraud, school request, appeal denied)

    /// Fail-closed decode: an unrecognised value from the backend is treated as
    /// `.unverified` (no access) rather than throwing. A decode failure on one
    /// field would otherwise drop the whole profile and mask the gate.
    init(from decoder: Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        self = EnrollmentStatus(rawValue: raw) ?? .unverified
    }

    /// True only for the two states allowed inside a campus community.
    var grantsCommunityAccess: Bool {
        self == .enrolled || self == .incoming
    }
}

// MARK: - School Gate Method

/// How a user proved they belong to a school. Recorded on the verification
/// record (never on the profile) for audit and abuse review.
enum SchoolGateMethod: String, Codable, CaseIterable {
    case eduMagicLink       // Phone + allowlisted .edu magic link
    case schoolOAuth        // School Google / Microsoft tenant OAuth
    case enrollmentProof    // Incoming-student admission/enrollment document
}

// MARK: - Student ID Verification Status

/// State of the student ID card photo + liveness check. Written exclusively by
/// `studentIdVerification.ts`. The underlying ID image and liveness frames live
/// under `users/{uid}/verification/**` (owner-only) and never touch the profile.
enum StudentIDStatus: String, Codable, CaseIterable {
    case none           // Not started
    case pending        // Uploaded, face match running
    case verified       // ID card photo + liveness passed
    case faceMatched    // ID ↔ liveness face match confirmed (Dating + NameDrop)
    case rejected       // Failed review — must retry

    /// Fail-closed decode: unknown backend values grant nothing.
    init(from decoder: Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        self = StudentIDStatus(rawValue: raw) ?? .none
    }

    /// Student ID card photo + liveness passed — the Quest Mode precondition.
    var isIDVerified: Bool {
        self == .verified || self == .faceMatched
    }

    /// ID ↔ liveness face match confirmed — the Dating and NameDrop precondition.
    var isFaceMatched: Bool {
        self == .faceMatched
    }
}
