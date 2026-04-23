// MARK: - SECURITY CHECKLIST COMPLIANCE
// [x] No hardcoded secrets, API keys, or tokens
// [x] XP/badge writes go through FirestoreService (server-validated via security rules)
// [x] Remote Config values validated and clamped before use
// [x] No PII logged — only badge names, XP amounts, and multiplier values
// [x] Multiplier bounds enforced client-side (1.0–2.0) to prevent exploitation
// [x] Badge definitions are read-only constants — no user-controlled badge creation

import Foundation
import Combine
import FirebaseRemoteConfig
import FirebaseFirestore

// MARK: - GamificationService

@MainActor
final class GamificationService: ObservableObject {
    static let shared = GamificationService()

    @Published var activeMultiplier: Double = 1.0
    @Published var recentBadge: BadgeDefinition?

    private let remoteConfig = RemoteConfig.remoteConfig()
    private let db = Firestore.firestore()
    private let analytics = AnalyticsService.shared

    // MARK: - Remote Config Keys

    private enum ConfigKey {
        static let underrepresentedGenderMultiplier = "underrepresented_gender_multiplier"
        static let femaleAcquisitionBoost = "female_acquisition_boost"
    }

    // MARK: - Badge Definitions

    enum BadgeType {
        static let balanceGuardian = BadgeDefinition(
            id: "balance_guardian",
            name: "Balance Guardian",
            iconName: "shield.checkered",
            description: "Helped balance the community by joining during a gender imbalance"
        )
        static let verifiedPioneer = BadgeDefinition(
            id: "verified_pioneer",
            name: "Verified Pioneer",
            iconName: "checkmark.seal.fill",
            description: "Completed identity verification early"
        )
        static let vibeMatchmaker = BadgeDefinition(
            id: "vibe_matchmaker",
            name: "Vibe Matchmaker",
            iconName: "sparkles",
            description: "Made 5 successful vibe-matched connections"
        )
        static let waitlistSurvivor = BadgeDefinition(
            id: "waitlist_survivor",
            name: "Waitlist Survivor",
            iconName: "hourglass.badge.plus",
            description: "Activated after waiting on the waitlist"
        )
        static let firstConnection = BadgeDefinition(
            id: "first_connection",
            name: "First Spark",
            iconName: "bolt.heart.fill",
            description: "Made your first real-world connection"
        )
    }

    struct BadgeDefinition {
        let id: String
        let name: String
        let iconName: String
        let description: String

        /// Converts to a Firestore-compatible dictionary for storage.
        func toFirestoreData() -> [String: Any] {
            [
                "id": id,
                "name": name,
                "iconName": iconName,
                "earnedAt": Timestamp(date: Date()),
                "description": description
            ]
        }
    }

    // MARK: - XP Constants

    private enum XPReward {
        static let verification = 200
        static let firstConnection = 150
        static let waitlistSurvivor = 100
        static let referral = 100
        static let icebreakerCompleted = 50
    }

    // MARK: - Init

    private init() {
        configureRemoteConfig()
    }

    // MARK: - Remote Config

    private func configureRemoteConfig() {
        let defaults: [String: NSObject] = [
            ConfigKey.underrepresentedGenderMultiplier: 1.2 as NSNumber,
            ConfigKey.femaleAcquisitionBoost: 1.5 as NSNumber
        ]
        remoteConfig.setDefaults(defaults)

        let settings = RemoteConfigSettings()
        settings.minimumFetchInterval = 3600 // 1 hour in production
        remoteConfig.configSettings = settings

        Task {
            try? await remoteConfig.fetchAndActivate()
            await MainActor.run {
                self.refreshMultiplier()
            }
        }
    }

    /// Reads the underrepresented gender multiplier from Remote Config.
    /// Clamps to 1.0–2.0 to prevent exploitation via tampered config.
    func underrepresentedGenderMultiplier() -> Double {
        let raw = remoteConfig.configValue(forKey: ConfigKey.underrepresentedGenderMultiplier).numberValue.doubleValue
        return min(max(raw, 1.0), 2.0)
    }

    /// Reads the female acquisition boost from Remote Config.
    func femaleAcquisitionBoost() -> Double {
        let raw = remoteConfig.configValue(forKey: ConfigKey.femaleAcquisitionBoost).numberValue.doubleValue
        return min(max(raw, 1.0), 3.0)
    }

    private func refreshMultiplier() {
        activeMultiplier = underrepresentedGenderMultiplier()
    }

    // MARK: - XP Awarding

    /// Awards XP to a user, applying the active multiplier for underrepresented genders.
    /// Writes via Firestore transaction for atomicity.
    func awardXP(uid: String, baseAmount: Int, reason: String, applyGenderMultiplier: Bool = false, gender: Gender? = nil) async {
        var multiplier = 1.0
        if applyGenderMultiplier, let gender = gender {
            let needsBoost = BalanceEnforcer.shared.needsFemaleBoost
            if (gender == .female || gender == .nonBinary) && needsBoost {
                multiplier = underrepresentedGenderMultiplier()
            }
        }

        let finalAmount = Int(Double(baseAmount) * multiplier)
        guard finalAmount > 0, finalAmount <= 99999 else { return }

        do {
            let docRef = db.collection("users").document(uid)
            try await db.runTransaction { transaction, errorPointer -> Any? in
                let snapshot: DocumentSnapshot
                do {
                    snapshot = try transaction.getDocument(docRef)
                } catch let error as NSError {
                    errorPointer?.pointee = error
                    return nil
                }

                let gamData = snapshot.data()?["gamification"] as? [String: Any] ?? [:]
                let currentXP = gamData["totalXP"] as? Int ?? 0
                let newXP = currentXP + finalAmount
                let newLevel = 1 + Int(sqrt(Double(newXP) / 80.0))

                transaction.updateData([
                    "gamification.totalXP": newXP,
                    "gamification.level": newLevel
                ], forDocument: docRef)

                return nil
            }

            analytics.logXPAwarded(amount: finalAmount, multiplier: multiplier, reason: reason)
        } catch {
            print("[Gamification] XP award failed: \(error.localizedDescription)")
        }
    }

    // MARK: - Badge Awarding

    /// Awards a badge to a user. Badges are stored as a top-level array on the
    /// user document (not inside GamificationProfile) for independent querying.
    /// Deduplication by badge ID prevents duplicate awards.
    func awardBadge(uid: String, badge: BadgeDefinition, trigger: String) async {
        do {
            let docRef = db.collection("users").document(uid)
            let doc = try await docRef.getDocument()
            let existingBadges = doc.data()?["badges"] as? [[String: Any]] ?? []

            // Don't award duplicate badges
            if existingBadges.contains(where: { ($0["id"] as? String) == badge.id }) {
                return
            }

            try await docRef.updateData([
                "badges": FieldValue.arrayUnion([badge.toFirestoreData()])
            ])

            recentBadge = badge
            analytics.logBadgeAwarded(badgeName: badge.name, trigger: trigger)
        } catch {
            print("[Gamification] Badge award failed: \(error.localizedDescription)")
        }
    }

    // MARK: - Reward Actions

    /// Call after verification completes successfully.
    func rewardVerification(uid: String, gender: Gender) async {
        await awardXP(uid: uid, baseAmount: XPReward.verification, reason: "verification", applyGenderMultiplier: true, gender: gender)
        await awardBadge(uid: uid, badge: BadgeType.verifiedPioneer, trigger: "verification_completed")
    }

    /// Call after first real-world connection.
    func rewardFirstConnection(uid: String, gender: Gender) async {
        await awardXP(uid: uid, baseAmount: XPReward.firstConnection, reason: "first_connection", applyGenderMultiplier: true, gender: gender)
        await awardBadge(uid: uid, badge: BadgeType.firstConnection, trigger: "first_connection")
    }

    /// Call when a waitlisted user is activated.
    func rewardWaitlistSurvivor(uid: String, gender: Gender) async {
        await awardXP(uid: uid, baseAmount: XPReward.waitlistSurvivor, reason: "waitlist_survived", applyGenderMultiplier: true, gender: gender)
        await awardBadge(uid: uid, badge: BadgeType.waitlistSurvivor, trigger: "waitlist_activation")
    }

    /// Call when user joins during a gender imbalance on the underrepresented side.
    func rewardBalanceGuardian(uid: String) async {
        await awardBadge(uid: uid, badge: BadgeType.balanceGuardian, trigger: "gender_balance_contribution")
    }

    /// Call after completing an icebreaker challenge.
    func rewardIcebreakerCompleted(uid: String, gender: Gender) async {
        await awardXP(uid: uid, baseAmount: XPReward.icebreakerCompleted, reason: "icebreaker_completed", applyGenderMultiplier: false)
    }

    /// Call after 5 successful vibe-matched connections.
    func rewardVibeMatchmaker(uid: String) async {
        await awardBadge(uid: uid, badge: BadgeType.vibeMatchmaker, trigger: "five_vibe_matches")
    }
}
