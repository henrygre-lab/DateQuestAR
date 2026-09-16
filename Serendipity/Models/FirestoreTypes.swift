// MARK: - SECURITY CHECKLIST COMPLIANCE (see docs/SECURITY_CHECKLIST.md)
// [x] No hardcoded secrets, API keys, or tokens
// [x] VerificationRecord lives at users/{uid}/verification/** — owner-only read,
//     Cloud-Function-only write (firestore.rules). It is never embedded in a
//     UserProfile, so it cannot leak through a nearby or match payload.
// [x] No image bytes on any type here — the record holds storage paths and
//     outcomes; the student ID photo and liveness frames stay in the
//     function-owned bucket prefix and are never client-readable
// [x] Phone number is stored only as a salted SHA256 hash for duplicate
//     detection; the plaintext lives in Keychain on-device and in Firebase Auth
// [x] Waitlist and gender stats are backend-write-only (firestore.rules)
// [x] Server timestamps throughout — never a client clock

import Foundation
import FirebaseFirestore

// MARK: - Waitlist Entry

struct WaitlistEntry: Codable, Identifiable {
    @DocumentID var id: String?
    var uid: String
    var gender: String
    var status: String                      // "queued", "activating", "activated"
    var entryTime: Timestamp
    var estimatedActivation: Timestamp?
    var activatedAt: Timestamp?

    /// Waitlisting is a Dating-only mechanism. A user queued here is still free
    /// to use Hangout, Study, Friendship and Event.
    var scopedToDating: Bool = true
}

// MARK: - Gender Stats

struct GenderStats: Codable {
    var totalActive: Int
    var maleCount: Int
    var femaleCount: Int
    var nonBinaryCount: Int
    var preferNotToSayCount: Int
    var malePct: Double
    var femalePct: Double
    var lastUpdated: Timestamp
    var femaleAlertCap: Int?
    var maleAlertCap: Int?
    var womenFirstQueuingEnabled: Bool?

    /// Which school this ratio describes. Balance is meaningless nationally —
    /// a 50/50 national split can still be a 90/10 campus. Nil only on the
    /// legacy global document.
    var schoolId: String?

    /// Counts cover Dating-gated users only (Dating on, or in cooldown). A campus
    /// that is 80% men on Study but balanced on Dating should not be throttled.
    var datingGatedOnly: Bool = true
}

// MARK: - Verification Record

/// The private verification subdocument at `users/{uid}/verification/{recordId}`.
///
/// Everything sensitive about identity lives here rather than on `UserProfile`:
/// storage paths for the student ID image and liveness frames, the gate method,
/// and the school email. `firestore.rules` makes this owner-read and
/// function-write only, so no other client can read it and the owner cannot
/// promote themselves by writing it.
struct VerificationRecord: Codable, Identifiable {
    @DocumentID var id: String?
    var uid: String

    // MARK: School gate

    /// How the school gate was passed. Audit trail for abuse review.
    var gateMethod: SchoolGateMethod?

    /// School issued by `schoolGate.ts`. Mirrors `UserProfile.schoolId`; this
    /// copy is the auditable one.
    var schoolId: String?

    /// The verified school email. Kept here rather than on the profile so that
    /// no other client can read it — a school address is a real name plus a
    /// campus, which is exactly what the community gate exists to protect.
    var schoolEmail: String?

    /// Salted SHA256 of the phone number, computed server-side, for duplicate
    /// and ban-evasion detection. The plaintext number never lands in Firestore.
    var phoneHash: String?

    // MARK: Student ID + liveness

    var studentIDStatus: StudentIDStatus = .none

    /// Storage path of the student ID card photo, under the function-owned
    /// prefix. Never under `photos/`, never a download URL, never client-readable.
    var studentIDStoragePath: String?

    /// Storage paths of the retained liveness frames, same prefix and handling.
    var livenessFrameStoragePaths: [String] = []

    /// ID ↔ liveness face-match score, 0.0–1.0, computed server-side.
    var faceMatchScore: Double?

    /// Date of birth read off the student ID, reduced to an age by the server.
    /// The DOB itself is not retained.
    var verifiedAge: Int?

    var submittedAt: Timestamp?
    var reviewedAt: Timestamp?

    /// Reason shown to the user on rejection. Generic by construction — it never
    /// says which check failed, so it cannot be used to probe the matcher.
    var rejectionReason: String?
}
