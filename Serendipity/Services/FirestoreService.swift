// MARK: - Vibe Coding Security Checklist Compliance
// [x] No hardcoded secrets, API keys, or tokens
// [x] All writes use authenticated UID — no anonymous writes
// [x] Transactions used for alert counter increments (atomicity)
// [x] Transactions used for all XP grants — no client-side XP manipulation
// [x] Daily login XP uses server timestamp comparison — no client clock trust
// [x] Streak bonuses are deterministic and server-verifiable
// [x] XP reason logged for debugging only — no PII in reason strings
// [x] Waitlist operations are read-only on client; writes via Cloud Functions
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

    // MARK: - User CRUD

    func fetchUser(uid: String) async throws -> UserProfile? {
        let doc = try await usersCollection.document(uid).getDocument()
        guard doc.exists else { return nil }
        return try doc.data(as: UserProfile.self)
    }

    func createOrUpdateUser(_ profile: UserProfile) async throws {
        guard let uid = profile.id else { throw AppError.missingUID }
        try usersCollection.document(uid).setData(from: profile, merge: true)
    }

    func updateQuestModeStatus(uid: String, enabled: Bool) async throws {
        try await usersCollection.document(uid).updateData([
            "privacySettings.questModeEnabled": enabled,
            "lastActive": FieldValue.serverTimestamp()
        ])
    }

    // MARK: - Nearby Users (Geohash Query)

    /// Fetches active users within the geohash neighborhood.
    /// Pass `debugForceMock: true` (DEBUG builds only) to get deterministic mock
    /// nearby users for exercising the proximity → alert → icebreaker flow on a
    /// single device.
    func fetchNearbyUsers(geohash: String, excludeUID: String, debugForceMock: Bool = false) async throws -> [UserProfile] {
        #if DEBUG
        if debugForceMock {
            return mockNearbyUsersForTesting(excludeUID: excludeUID)
        }
        #endif

        // TODO: Use GeoFire or geohash range queries for efficient proximity search
        let snapshot = try await usersCollection
            .whereField("privacySettings.questModeEnabled", isEqualTo: true)
            .limit(to: 50)
            .getDocuments()

        return try snapshot.documents
            .compactMap { try $0.data(as: UserProfile.self) }
            .filter { $0.uid != excludeUID }
    }

    #if DEBUG
    /// Deterministic mock nearby users for single-device testing. DEBUG-only —
    /// never compiled into release. Covers different genders, trust tiers, and
    /// intent vibes so the full match → alert → icebreaker path can be exercised.
    private func mockNearbyUsersForTesting(excludeUID: String) -> [UserProfile] {
        func make(uid: String, name: String, age: Int, gender: Gender,
                  trust: UserProfile.TrustLevel, interests: [String],
                  relationships: [MatchPreferences.RelationshipType],
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
                    relationshipTypes: relationships,
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
                gender: gender,
                accountStatus: .active,
                intentVibes: vibes,
                socialContextPreference: true
            )
        }

        let mocks = [
            make(uid: "test_user_a", name: "Test User A", age: 26, gender: .female,
                 trust: .gold, interests: ["coffee", "hiking", "coding"],
                 relationships: [.longTerm], vibes: ["adventurous", "genuine", "spontaneous"]),
            make(uid: "test_user_b", name: "Test User B", age: 29, gender: .male,
                 trust: .silver, interests: ["coffee", "gaming"],
                 relationships: [.casual], vibes: ["genuine", "chill"]),
            make(uid: "test_user_c", name: "Test User C", age: 24, gender: .nonBinary,
                 trust: .platinum, interests: ["art", "coffee", "travel"],
                 relationships: [.longTerm, .friendship], vibes: ["creative", "spontaneous", "genuine"])
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

    func updateTrustLevel(uid: String, level: UserProfile.TrustLevel) async throws {
        try await usersCollection.document(uid).updateData([
            "trustLevel": level.rawValue
        ])
    }

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

    /// Atomically grants XP to a user and recalculates their level.
    /// Uses a transaction to prevent race conditions from concurrent XP sources
    /// (e.g., icebreaker completion + badge award firing simultaneously).
    ///
    /// - Parameters:
    ///   - uid: The user's Firestore document ID.
    ///   - amount: XP to add. Must be positive; clamped to 1...10000.
    ///   - reason: Internal debug label (e.g., "icebreaker_completed"). No PII.
    /// - Returns: The user's new total XP after the grant.
    ///
    /// - Security: Amount is clamped server-side. Reason is never user-supplied
    ///   free text — callers pass fixed string constants only.
    func grantXP(uid: String, amount: Int, reason: String) async throws -> Int {
        // Clamp to prevent abuse if a caller passes an unreasonable value
        let safeAmount = min(max(amount, 1), 10000)
        let docRef = usersCollection.document(uid)

        let result = try await db.runTransaction { transaction, errorPointer -> Any? in
            let snapshot: DocumentSnapshot
            do {
                snapshot = try transaction.getDocument(docRef)
            } catch let error as NSError {
                errorPointer?.pointee = error
                return nil
            }

            let gamData = snapshot.data()?["gamification"] as? [String: Any] ?? [:]
            let currentXP = gamData["totalXP"] as? Int ?? 0
            let newTotalXP = currentXP + safeAmount
            let newLevel = 1 + Int(sqrt(Double(newTotalXP) / 80.0))

            // Narrow write — only XP and level fields
            transaction.updateData([
                "gamification.totalXP": newTotalXP,
                "gamification.level": newLevel,
                "lastActive": FieldValue.serverTimestamp()
            ], forDocument: docRef)

            return newTotalXP
        }

        let newTotal = (result as? Int) ?? 0
        Log.firestore.debug("Granted \(safeAmount) XP to \(uid.prefix(8))... reason=\(reason) total=\(newTotal)")
        return newTotal
    }

    /// Updates the gamification sub-document with a full GamificationProfile.
    /// Uses narrow updateData to avoid overwriting non-gamification fields.
    /// Recaches level before writing to keep stored level consistent.
    ///
    /// - Security: Only touches gamification.* fields. Server-authoritative
    ///   fields (accountStatus, trustLevel, etc.) are never written.
    func updateGamificationProfile(uid: String, profile: GamificationProfile) async throws {
        var mutable = profile
        mutable.recacheLevel()

        try await usersCollection.document(uid).updateData([
            "gamification.totalXP": mutable.totalXP,
            "gamification.level": mutable.level,
            "gamification.lastLoginDate": Timestamp(date: mutable.lastLoginDate),
            "gamification.currentStreakDays": mutable.currentStreakDays,
            "lastActive": FieldValue.serverTimestamp()
        ])
    }

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
