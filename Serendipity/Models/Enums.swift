// MARK: - Vibe Coding Security Checklist Compliance
// [x] No hardcoded secrets, API keys, or tokens
// [x] All Firestore writes require Firebase Auth UID ownership check
// [x] Minimal data exposure — enums are value types with no PII
// [x] No client-side trust decisions — server/rules enforce status transitions
// [x] Codable raw values are safe string literals only

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
