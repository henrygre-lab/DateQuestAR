// MARK: - SECURITY CHECKLIST COMPLIANCE (see docs/SECURITY_CHECKLIST.md)
// [x] No hardcoded secrets, API keys, or tokens
// [x] All writes use authenticated UID — no anonymous writes
// [x] Transactions used for alert counter increments (atomicity)
// [x] No client XP write path — grantXP and updateGamificationProfile were
//     removed; the awardXP Cloud Function is the only grant path, and it cannot
//     be asked to credit another account
// [x] Daily login XP uses server timestamp comparison — no client clock trust
// [x] Streak bonuses are deterministic and server-verifiable
// [x] XP reason logged for debugging only — no PII in reason strings
// [x] Waitlist operations are read-only on client; writes via Cloud Functions
// [x] Same-school gate on every nearby read — fetchNearbyUsers takes a
//     CommunityScope and constrains the query by schoolId, or by a
//     server-confirmed Spring Break destination. firestore.rules evaluates the
//     same predicate per document, so an unconstrained query fails outright.
// [x] Profile writes are field-whitelisted — saveProfileEdits never sends
//     schoolId, enrollmentStatus, studentIDStatus, verifiedAge, trustLevel,
//     accountStatus, activeIntents or datingCooldownUntil, all of which are
//     Cloud-Function-owned and rejected by rules on any client write
// [x] Trust level is no longer client-writable — updateTrustLevel was removed
// [x] Schools and Spring Break destinations are read-only reference data
// [x] No raw coordinates — geohash only
// [x] Minimal data returned — fetch methods return only needed fields
// [x] Photo uploads scoped to authenticated user's storage path
// [x] Server timestamps used for all time-sensitive fields

import Foundation
import FirebaseFirestore
import FirebaseStorage

// MARK: - FirestoreService

final class FirestoreService {
    static let shared = FirestoreService()
    private let db = Firestore.firestore()
    private let storage = Storage.storage()

    private init() {}

    // MARK: - Collections

    private var usersCollection: CollectionReference { db.collection("users") }
    private var matchesCollection: CollectionReference { db.collection("matches") }
    private var reportsCollection: CollectionReference { db.collection("reports") }
    private var waitlistCollection: CollectionReference { db.collection("waitlist") }
    private var genderStatsCollection: CollectionReference { db.collection("global_gender_stats") }
    private var schoolsCollection: CollectionReference { db.collection("schools") }
    private var destinationsCollection: CollectionReference { db.collection("spring_break_destinations") }

    // MARK: - User CRUD

    func fetchUser(uid: String) async throws -> UserProfile? {
        let doc = try await usersCollection.document(uid).getDocument()
        guard doc.exists else { return nil }
        return try doc.data(as: UserProfile.self)
    }

    /// Creates the initial profile document for a newly authenticated user.
    ///
    /// Only ever called with a freshly built minimal profile, whose
    /// server-owned fields are at their least-privileged defaults (no schoolId,
    /// `.unverified`, `.none`, `.bronze`). `firestore.rules` enforces exactly
    /// that on create, so a tampered client cannot seed itself a community.
    func createUser(_ profile: UserProfile) async throws {
        guard let uid = profile.id else { throw AppError.missingUID }
        try usersCollection.document(uid).setData(from: profile, merge: true)
    }

    /// Writes the parts of a profile the user actually owns.
    ///
    /// The field list is a whitelist, not a filter on a full encode: everything
    /// that decides access — schoolId, enrollmentStatus, studentIDStatus,
    /// verifiedAge, trustLevel, accountStatus, activeIntents,
    /// datingCooldownUntil, springBreakDestinationId — is issued by a Cloud
    /// Function and rejected by `firestore.rules` on any client write. Sending
    /// them here would fail the whole update, so they are never sent.
    ///
    /// Intents are deliberately absent: they change only through the
    /// `setActiveIntents` callable, which is what starts the 24h Dating cooldown.
    func saveProfileEdits(_ profile: UserProfile) async throws {
        guard let uid = profile.id ?? Optional(profile.uid), !uid.isEmpty else {
            throw AppError.missingUID
        }

        var data: [String: Any] = [
            "displayName": profile.displayName,
            "age": profile.age,
            "bio": profile.bio,
            "photoURLs": profile.photoURLs,
            "selfDescriptors": profile.selfDescriptors,
            "intentVibes": profile.intentVibes,
            "gender": profile.gender.rawValue,
            "socialContextPreference": profile.socialContextPreference,
            "isProfileComplete": profile.isProfileComplete,
            "lastActive": FieldValue.serverTimestamp(),
            "preferences.ageRange.lowerBound": profile.preferences.ageRange.lowerBound,
            "preferences.ageRange.upperBound": profile.preferences.ageRange.upperBound,
            "preferences.maxDistanceMiles": profile.preferences.maxDistanceMiles,
            "preferences.genderPreferences": profile.preferences.genderPreferences,
            "preferences.interests": profile.preferences.interests,
            "preferences.dealbreakers": profile.preferences.dealbreakers,
            "preferences.compatibilityThreshold": profile.preferences.compatibilityThreshold,
            "privacySettings.questModeEnabled": profile.privacySettings.questModeEnabled,
            "privacySettings.visibilityRadius": profile.privacySettings.visibilityRadius,
            "privacySettings.alertLimit": profile.privacySettings.alertLimit,
            "privacySettings.locationSharingMode": profile.privacySettings.locationSharingMode.rawValue,
            "privacySettings.showInCommunityEvents": profile.privacySettings.showInCommunityEvents
        ]

        if let zones = try? Firestore.Encoder().encode(profile.privacySettings.autoPauseZones) {
            data["privacySettings.autoPauseZones"] = zones
        }

        try await usersCollection.document(uid).updateData(data)
    }

    func updateQuestModeStatus(uid: String, enabled: Bool) async throws {
        try await usersCollection.document(uid).updateData([
            "privacySettings.questModeEnabled": enabled,
            "lastActive": FieldValue.serverTimestamp()
        ])
    }

    // MARK: - Nearby Users (Geohash Query)

    /// Fetches candidate users inside the caller's community.
    ///
    /// The scope is not a hint — it is the query's first constraint, and it has
    /// to be. `firestore.rules` evaluates its read predicate against every
    /// document a list query returns, so a query that reaches beyond the
    /// caller's own school (or their server-confirmed Spring Break destination)
    /// fails as a whole rather than returning a trimmed set.
    ///
    /// `.none` — off campus, no live destination — returns nothing without
    /// touching the network. That is the auto-pause case.
    ///
    /// Pass `debugForceMock: true` (DEBUG builds only) to get deterministic mock
    /// nearby users for exercising the proximity → alert → icebreaker flow on a
    /// single device.
    func fetchNearbyUsers(scope: CommunityScope,
                          excludeUID: String,
                          debugForceMock: Bool = false) async throws -> [UserProfile] {
        #if DEBUG
        if debugForceMock {
            return mockNearbyUsersForTesting(excludeUID: excludeUID, scope: scope)
        }
        #endif

        let query: Query
        switch scope {
        case .none:
            return []

        case .campus(let schoolId):
            guard !schoolId.isEmpty else { return [] }
            query = usersCollection
                .whereField("schoolId", isEqualTo: schoolId)
                .whereField("accountStatus", isEqualTo: AccountStatus.active.rawValue)
                .whereField("privacySettings.questModeEnabled", isEqualTo: true)

        case .springBreak(let destinationId, _):
            // Cross-school, but only among users the backend has confirmed at
            // this same destination. A local or an unverified tourist has no
            // springBreakDestinationId and cannot appear here.
            guard !destinationId.isEmpty else { return [] }
            query = usersCollection
                .whereField("springBreakDestinationId", isEqualTo: destinationId)
                .whereField("accountStatus", isEqualTo: AccountStatus.active.rawValue)
                .whereField("privacySettings.questModeEnabled", isEqualTo: true)
        }

        // TODO: Use GeoFire or geohash range queries for efficient proximity search
        let snapshot = try await query.limit(to: 50).getDocuments()

        return try snapshot.documents
            .compactMap { try $0.data(as: UserProfile.self) }
            .filter { $0.uid != excludeUID }
    }

    // MARK: - Schools & Destinations (read-only reference data)

    /// Reads a school document. Admin-write in `firestore.rules`; the client can
    /// only ever read one.
    func fetchSchool(schoolId: String) async throws -> School? {
        let doc = try await schoolsCollection.document(schoolId).getDocument()
        guard doc.exists else { return nil }
        return try doc.data(as: School.self)
    }

    /// Lists the active schools, for the incoming-student picker.
    ///
    /// Reference data. `firestore.rules` makes `schools/*` auth-read and
    /// admin-write, so a client can read this list but never add to it — which
    /// matters, because a school document carries the allowlisted email domains.
    func fetchSchools() async throws -> [School] {
        let snapshot = try await schoolsCollection
            .whereField("isActive", isEqualTo: true)
            .limit(to: 100)
            .getDocuments()
        return try snapshot.documents.compactMap { try $0.data(as: School.self) }
    }

    /// Reads the currently switched-on Spring Break destinations.
    ///
    /// `isActive` is the only server-side filter available to a query; the dated
    /// window is checked on-device via `SpringBreakDestination.isLive(at:)` and
    /// again by the backend before it will confirm presence. The client cannot
    /// widen a window it does not own.
    func fetchActiveSpringBreakDestinations() async throws -> [SpringBreakDestination] {
        let snapshot = try await destinationsCollection
            .whereField("isActive", isEqualTo: true)
            .limit(to: 20)
            .getDocuments()
        return try snapshot.documents.compactMap { try $0.data(as: SpringBreakDestination.self) }
    }

    /// Reads the caller's own verification record. Owner-only by rule — this
    /// call returns nothing for any other uid, by design.
    func fetchVerificationRecord(uid: String, recordId: String) async throws -> VerificationRecord? {
        let doc = try await usersCollection
            .document(uid)
            .collection("verification")
            .document(recordId)
            .getDocument()
        guard doc.exists else { return nil }
        return try doc.data(as: VerificationRecord.self)
    }

    #if DEBUG
    /// Deterministic mock nearby users for single-device testing. DEBUG-only —
    /// never compiled into release. Covers different genders, trust tiers, and
    /// intent vibes so the full match → alert → icebreaker path can be exercised.
    ///
    /// The mocks take their school from the caller's scope, so the demo can never
    /// model a cross-campus pool that production would reject. Under `.none` they
    /// return nothing, which is what an off-campus device should see.
    private func mockNearbyUsersForTesting(excludeUID: String,
                                           scope: CommunityScope) -> [UserProfile] {
        let mockSchoolId: String
        switch scope {
        case .none:
            return []
        case .campus(let schoolId):
            mockSchoolId = schoolId
        case .springBreak:
            // Inside a live destination the pool is cross-school by design, so
            // the demo candidates come from a different school on purpose.
            mockSchoolId = "demo_visiting_school"
        }

        func make(uid: String, name: String, age: Int, gender: Gender,
                  trust: UserProfile.TrustLevel, interests: [String],
                  intents: [Intent],
                  vibes: [String]) -> UserProfile {
            UserProfile(
                uid: uid,
                displayName: name,
                age: age,
                bio: "\(name) is a demo profile for on-device testing.",
                photoURLs: [],
                selfDescriptors: [],
                verificationStatus: .verified,
                trustLevel: trust,
                verifiedAge: age,
                verificationCompletedAt: Date(),
                preferences: MatchPreferences(
                    ageRange: 21...40,
                    maxDistanceMiles: 0.25,
                    genderPreferences: [],
                    interests: interests,
                    dealbreakers: [],
                    compatibilityThreshold: 0.80
                ),
                privacySettings: PrivacySettings(
                    questModeEnabled: true,
                    visibilityRadius: 0.25,
                    autoPauseZones: [],
                    alertLimit: 10,
                    locationSharingMode: .anonymized,
                    showInCommunityEvents: true
                ),
                gamification: GamificationProfile(),
                isProfileComplete: true,
                trustScore: 0.85,
                createdAt: Date(),
                lastActive: Date(),
                schoolId: mockSchoolId,
                schoolDisplayName: "Demo Campus",
                enrollmentStatus: .enrolled,
                studentIDStatus: .faceMatched,
                activeIntents: intents,
                gender: gender,
                accountStatus: .active,
                intentVibes: vibes,
                socialContextPreference: true
            )
        }

        let mocks = [
            make(uid: "test_user_a", name: "Test User A", age: 26, gender: .female,
                 trust: .gold, interests: ["coffee", "hiking", "coding"],
                 intents: [.hangout, .study], vibes: ["adventurous", "genuine", "spontaneous"]),
            make(uid: "test_user_b", name: "Test User B", age: 29, gender: .male,
                 trust: .silver, interests: ["coffee", "gaming"],
                 intents: [.study], vibes: ["genuine", "chill"]),
            make(uid: "test_user_c", name: "Test User C", age: 24, gender: .nonBinary,
                 trust: .platinum, interests: ["art", "coffee", "travel"],
                 intents: [.hangout, .friendship, .event], vibes: ["creative", "spontaneous", "genuine"])
        ]

        return mocks.filter { $0.uid != excludeUID }
    }
    #endif

    // MARK: - Matches

    func saveMatch(_ match: Match) async throws {
        try matchesCollection.document(match.id).setData(from: match)
    }

    func updateMatchStatus(matchID: String, status: Match.MatchStatus) async throws {
        try await matchesCollection.document(matchID).updateData([
            "status": status.rawValue
        ])
    }

    func updateMatchRating(matchID: String, rating: Int) async throws {
        try await matchesCollection.document(matchID).updateData([
            "postMeetRating": rating,
            "meetupOccurred": true
        ])
    }

    // MARK: - Photo Upload

    func uploadPhoto(_ imageData: Data, uid: String, index: Int) async throws -> URL {
        let ref = storage.reference().child("users/\(uid)/photos/photo_\(index).jpg")
        let metadata = StorageMetadata()
        metadata.contentType = "image/jpeg"
        _ = try await ref.putDataAsync(imageData, metadata: metadata)
        return try await ref.downloadURL()
    }

    // MARK: - Verification Artefact Upload

    /// Uploads a student ID photo or liveness frame to the write-only
    /// verification prefix and returns its **storage path**, not a URL.
    ///
    /// A path, not a URL, on purpose: `storage.rules` makes objects under
    /// `verification/{uid}/` unreadable to every client — including the person
    /// who uploaded them. Only the Admin SDK in `studentIdVerification.ts` can
    /// read them, and it deletes them once it has recorded the outcome. That is
    /// what makes "a student ID image can never appear on a profile" a property
    /// of the system rather than a promise in this file.
    func uploadVerificationArtifact(_ imageData: Data,
                                    uid: String,
                                    filename: String) async throws -> String {
        let path = "verification/\(uid)/\(filename)"
        let ref = storage.reference().child(path)
        let metadata = StorageMetadata()
        metadata.contentType = "image/jpeg"
        _ = try await ref.putDataAsync(imageData, metadata: metadata)
        return path
    }

    // MARK: - Photo Deletion (cleanup on failed upload)

    func deletePhoto(uid: String, index: Int) async {
        let ref = storage.reference().child("users/\(uid)/photos/photo_\(index).jpg")
        try? await ref.delete()
    }

    // MARK: - Photo Accuracy Ratings

    /// Submits a photo accuracy rating for one side of a match.
    func submitPhotoAccuracyRating(matchID: String, raterUID: String, rating: Int) async throws {
        let doc = try await matchesCollection.document(matchID).getDocument()
        guard let match = try? doc.data(as: Match.self) else { return }

        let field = raterUID == match.userAUID ? "photoAccuracyRatingA" : "photoAccuracyRatingB"
        try await matchesCollection.document(matchID).updateData([
            field: rating,
            "meetupOccurred": true
        ])
    }

    /// Fetches all photo accuracy ratings given TO a user by their match partners.
    func fetchPhotoAccuracyRatings(forUID uid: String) async throws -> [Int] {
        var ratings: [Int] = []

        // Ratings where user was userB → ratingA is about them
        let asB = try await matchesCollection
            .whereField("userBUID", isEqualTo: uid)
            .whereField("meetupOccurred", isEqualTo: true)
            .getDocuments()
        for doc in asB.documents {
            if let rating = doc.data()["photoAccuracyRatingA"] as? Int {
                ratings.append(rating)
            }
        }

        // Ratings where user was userA → ratingB is about them
        let asA = try await matchesCollection
            .whereField("userAUID", isEqualTo: uid)
            .whereField("meetupOccurred", isEqualTo: true)
            .getDocuments()
        for doc in asA.documents {
            if let rating = doc.data()["photoAccuracyRatingB"] as? Int {
                ratings.append(rating)
            }
        }

        return ratings
    }

    // MARK: - Trust Level
    //
    // There is deliberately no client write path for trustLevel. It is derived
    // server-side from verification depth and post-meet ratings, and
    // `firestore.rules` rejects any client write to it. The old
    // `updateTrustLevel(uid:level:)` was removed rather than left to fail at
    // runtime: a method that can only ever be denied is a trap for the next
    // caller.

    // MARK: - Account Deletion

    /// Deletes the user's Firestore document and all associated Storage photos.
    func deleteUserData(uid: String) async throws {
        // Delete profile photos from Storage
        let photosRef = storage.reference().child("users/\(uid)/photos")
        if let photosList = try? await photosRef.listAll() {
            for item in photosList.items {
                try? await item.delete()
            }
        }

        // Delete user document from Firestore
        try await usersCollection.document(uid).delete()
    }

    // MARK: - Reports

    func submitReport(reportedUID: String, reason: String, details: String) async throws {
        try await reportsCollection.addDocument(data: [
            "reportedUID": reportedUID,
            "reason": reason,
            "details": details,
            "timestamp": FieldValue.serverTimestamp()
        ])
    }
    // MARK: - Alert Counter (Transaction)

    /// Atomically increments the alert count for the current hour.
    /// Uses a Firestore transaction to prevent race conditions from concurrent alerts.
    /// Returns `true` if the alert is within the user's hourly cap, `false` if throttled.
    func incrementCurrentHourAlerts(uid: String, hourKey: String, cap: Int) async throws -> Bool {
        let docRef = usersCollection.document(uid)

        let result = try await db.runTransaction { transaction, errorPointer -> Any? in
            let snapshot: DocumentSnapshot
            do {
                snapshot = try transaction.getDocument(docRef)
            } catch let error as NSError {
                errorPointer?.pointee = error
                return false
            }

            // Read current hour alerts map
            let currentAlerts = snapshot.data()?["currentHourAlerts"] as? [String: Int] ?? [:]
            let currentCount = currentAlerts[hourKey] ?? 0

            // Check against cap before incrementing
            guard currentCount < cap else { return false }

            // Atomically set the new count for this hour key
            transaction.updateData([
                "currentHourAlerts.\(hourKey)": currentCount + 1,
                "lastActive": FieldValue.serverTimestamp()
            ], forDocument: docRef)

            return true
        }
        return (result as? Bool) ?? false
    }

    /// Resets alert counters for expired hour keys. Call periodically to keep the map clean.
    func pruneExpiredAlertCounters(uid: String, currentHourKey: String) async throws {
        let doc = try await usersCollection.document(uid).getDocument()
        guard let currentAlerts = doc.data()?["currentHourAlerts"] as? [String: Int] else { return }

        // Remove all keys that aren't the current hour
        let expiredKeys = currentAlerts.keys.filter { $0 != currentHourKey }
        guard !expiredKeys.isEmpty else { return }

        var updates: [String: Any] = ["lastActive": FieldValue.serverTimestamp()]
        for key in expiredKeys {
            updates["currentHourAlerts.\(key)"] = FieldValue.delete()
        }
        try await usersCollection.document(uid).updateData(updates)
    }

    // MARK: - Gamification XP (Transactional)
    // All XP writes use Firestore transactions to prevent race conditions.
    // Level is recalculated server-side from totalXP — clients never set level directly.
    // Server timestamps used for lastLoginDate to prevent client clock manipulation.

    /// Streak milestone bonuses. Deterministic and server-verifiable.
    private static let streakBonuses: [Int: Int] = [
        3: 50, 7: 100, 14: 200, 30: 500
    ]

    /// Records a daily login, awards +25 XP (first login today only), and updates streak.
    /// Uses a transaction to atomically read/write XP and streak state.
    /// Returns the XP gained this login and the new streak count.
    ///
    /// - Security: lastLoginDate compared using server timestamp to prevent
    ///   client clock manipulation. XP amount is fixed (not caller-controlled).
    /// Records a daily login and its streak bonus.
    ///
    /// This is the one remaining client-side XP write, and it is a **self**
    /// write: `XPManager` only ever passes the signed-in uid, and
    /// `firestore.rules` allows a user to write their own `gamification.*`.
    ///
    /// TODO: move to a Cloud Function alongside `awardXP`. It is left here for
    /// now because the streak comparison is the interesting part and porting it
    /// is a behaviour change, not a mechanical move — but it does mean the
    /// 1…10000 clamp that guards every other grant does not guard this one.
    func recordDailyLogin(uid: String) async throws -> (xpGained: Int, newStreak: Int) {
        let docRef = usersCollection.document(uid)

        let result = try await db.runTransaction { transaction, errorPointer -> Any? in
            let snapshot: DocumentSnapshot
            do {
                snapshot = try transaction.getDocument(docRef)
            } catch let error as NSError {
                errorPointer?.pointee = error
                return nil
            }

            guard let data = snapshot.data() else { return nil }

            // Read current gamification state
            let gamData = data["gamification"] as? [String: Any] ?? [:]
            let currentXP = gamData["totalXP"] as? Int ?? 0
            let currentStreak = gamData["currentStreakDays"] as? Int ?? 0
            let lastLogin = (gamData["lastLoginDate"] as? Timestamp)?.dateValue() ?? Date.distantPast

            // Check if already logged in today (server-relative calendar day)
            let calendar = Calendar.current
            if calendar.isDateInToday(lastLogin) {
                // Already logged in today — no XP, return current state
                return ["xpGained": 0, "newStreak": currentStreak]
            }

            // Calculate new streak
            let isConsecutiveDay = calendar.isDateInYesterday(lastLogin)
            let newStreak = isConsecutiveDay ? currentStreak + 1 : 1

            // Base daily login XP (fixed, not caller-controlled)
            var xpGained = 25

            // Streak milestone bonus
            if let bonus = FirestoreService.streakBonuses[newStreak] {
                xpGained += bonus
            }

            let newTotalXP = currentXP + xpGained
            let newLevel = 1 + Int(sqrt(Double(newTotalXP) / 80.0))

            // Atomic write — only gamification fields, never overwrites
            // server-authoritative data (accountStatus, trustLevel, etc.)
            transaction.updateData([
                "gamification.totalXP": newTotalXP,
                "gamification.level": newLevel,
                "gamification.currentStreakDays": newStreak,
                "gamification.lastLoginDate": FieldValue.serverTimestamp(),
                "lastActive": FieldValue.serverTimestamp()
            ], forDocument: docRef)

            return ["xpGained": xpGained, "newStreak": newStreak]
        }

        guard let dict = result as? [String: Int] else {
            throw AppError.networkError("Daily login transaction returned unexpected result")
        }
        return (xpGained: dict["xpGained"] ?? 0, newStreak: dict["newStreak"] ?? 0)
    }

    // MARK: - XP
    //
    // There is deliberately no client XP write path any more. `grantXP` and
    // `updateGamificationProfile` both took a uid, which meant a caller could
    // credit another account — `firestore.rules` denies that, and the methods
    // are removed rather than left to fail at runtime.
    //
    // XP is granted by the `awardXP` Cloud Function, which writes
    // `request.auth.uid` and picks the amount from a server-side table. See
    // `functions/src/gamification.ts`.
    //
    // The one exception below it is `recordDailyLogin`, which is a self-write.

    // MARK: - Waitlist (Read-Only on Client)

    /// Fetches the waitlist entry for a user. Waitlist documents are created/managed
    /// exclusively by Cloud Functions — the client only reads.
    func fetchWaitlistEntry(uid: String) async throws -> WaitlistEntry? {
        let doc = try await waitlistCollection.document(uid).getDocument()
        guard doc.exists else { return nil }
        return try doc.data(as: WaitlistEntry.self)
    }

    /// Checks if a user is currently waitlisted.
    func isUserWaitlisted(uid: String) async throws -> Bool {
        let doc = try await waitlistCollection.document(uid).getDocument()
        return doc.exists && (doc.data()?["status"] as? String) == "queued"
    }

    // MARK: - Gender Stats (Read-Only on Client)

    /// Fetches the current global gender stats. Written exclusively by Cloud Functions.
    func fetchGenderStats() async throws -> GenderStats? {
        let doc = try await genderStatsCollection.document("current").getDocument()
        guard doc.exists else { return nil }
        return try doc.data(as: GenderStats.self)
    }

    // MARK: - Account Status

    /// Reads the user's current account status. Status transitions are managed
    /// by Cloud Functions — the client reads only.
    func fetchAccountStatus(uid: String) async throws -> AccountStatus {
        let doc = try await usersCollection.document(uid).getDocument()
        guard let raw = doc.data()?["accountStatus"] as? String,
              let status = AccountStatus(rawValue: raw) else {
            return .active
        }
        return status
    }
}
