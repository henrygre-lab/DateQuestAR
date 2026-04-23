// MARK: - SECURITY CHECKLIST COMPLIANCE (see SECURITY_CHECKLIST.md)
// [x] No hardcoded secrets, API keys, or tokens
// [x] All XP writes go through FirestoreService transactions — no client-side manipulation
// [x] XP amounts are fixed constants, not caller-controlled or user-editable
// [x] Level derived from totalXP via deterministic formula — cached value is advisory
// [x] No PII in logs — only truncated UIDs and XP amounts
// [x] Local gamification state is a read cache; Firestore is authoritative
// [x] Addresses gamification momentum from POTENTIAL_ISSUES.md Risk #5 (dead zones)
//     and Risk #3 (swarm) by rewarding icebreaker/NameDrop completion over passive use

import Foundation
import FirebaseAuth

// MARK: - XPManager

/// Central manager for the simplified XP system. All XP mutations flow through
/// FirestoreService transactions — the local `currentGamification` is a read
/// cache for UI responsiveness, not a source of truth.
///
/// Integration: call `loadCurrentUserGamification()` from AuthViewModel on
/// successful sign-in or from app launch when a user session already exists.
@MainActor
final class XPManager: ObservableObject {
    static let shared = XPManager()

    // MARK: - Published State

    @Published var currentGamification: GamificationProfile?

    // MARK: - XP Award Constants
    // Fixed amounts — never user-supplied. Changing these changes game balance,
    // so treat as a product decision, not a config value.

    /// XP awarded for completing an AR icebreaker challenge.
    private let icebreakerXP = 50

    /// XP awarded for a successful NameDrop (mutual profile exchange).
    private let nameDropXP = 100

    // MARK: - Dependencies

    private let firestoreService = FirestoreService.shared
    private let analytics = AnalyticsService.shared

    private init() {}

    // MARK: - Profile Loading

    /// Loads the current user's gamification state from Firestore.
    /// Call from AuthViewModel on sign-in or app launch.
    func loadCurrentUserGamification() async {
        guard let uid = Auth.auth().currentUser?.uid else {
            print("[XPManager] No authenticated user — skipping gamification load")
            return
        }

        do {
            if let profile = try await firestoreService.fetchUser(uid: uid) {
                currentGamification = profile.gamification
            }
        } catch {
            print("[XPManager] Failed to load gamification: \(error.localizedDescription)")
        }
    }

    // MARK: - Daily Login

    /// Records a daily login via FirestoreService transaction.
    /// Awards +25 XP on first login today, plus streak milestone bonuses.
    /// Idempotent — calling multiple times in the same day is safe (no duplicate XP).
    func recordDailyLogin() async {
        guard let uid = Auth.auth().currentUser?.uid else { return }

        do {
            let result = try await firestoreService.recordDailyLogin(uid: uid)

            // Update local cache to reflect new state
            if result.xpGained > 0 {
                currentGamification?.totalXP += result.xpGained
                currentGamification?.currentStreakDays = result.newStreak
                currentGamification?.lastLoginDate = Date()
                currentGamification?.recacheLevel()

                analytics.logXPAwarded(
                    amount: result.xpGained,
                    multiplier: 1.0,
                    reason: "daily_login_streak_\(result.newStreak)"
                )
            }
        } catch {
            print("[XPManager] Daily login failed: \(error.localizedDescription)")
        }
    }

    // MARK: - Icebreaker XP

    /// Awards XP for completing an AR icebreaker challenge.
    /// Call from MatchManager/RevealManager after icebreaker success.
    func grantIcebreakerXP() async {
        await grantXP(amount: icebreakerXP, reason: "icebreaker_completed")
    }

    // MARK: - NameDrop XP

    /// Awards XP for a successful NameDrop (mutual profile exchange).
    /// Call from RevealManager.completeReveal after both users consent.
    func grantNameDropXP() async {
        await grantXP(amount: nameDropXP, reason: "namedrop_completed")
    }

    // MARK: - Level Query

    /// Returns the user's current level. Defaults to 1 if no profile is loaded.
    func getCurrentLevel() -> Int {
        return currentGamification?.computedLevel ?? 1
    }

    // MARK: - XP Progress (for UI progress bar)

    /// Returns the XP progress within the current level for UI display.
    /// - `current`: XP earned within this level
    /// - `needed`: total XP required to reach the next level
    ///
    /// Formula: level = 1 + floor(sqrt(totalXP / 80))
    /// Inverting: XP threshold for level N = (N - 1)² × 80
    func getXPProgressToNextLevel() -> (current: Int, needed: Int) {
        let totalXP = currentGamification?.totalXP ?? 0
        let level = getCurrentLevel()

        // XP threshold to reach current level: (level - 1)² × 80
        let currentLevelThreshold = (level - 1) * (level - 1) * 80

        // XP threshold to reach next level: level² × 80
        let nextLevelThreshold = level * level * 80

        let progressInLevel = totalXP - currentLevelThreshold
        let xpNeededForLevel = nextLevelThreshold - currentLevelThreshold

        return (current: max(0, progressInLevel), needed: max(1, xpNeededForLevel))
    }

    // MARK: - Milestone Rewards (Detection Only)
    // Stub for future reward granting (visibility boosts, event invites, etc.).
    // Currently returns which milestones a user has reached — real fulfillment
    // will be added when the reward backend is implemented.

    /// A milestone reward unlocked at a specific XP threshold.
    struct Reward: Equatable {
        let id: String
        let name: String
        let xpThreshold: Int
        let description: String
    }

    /// All available milestone rewards, ordered by XP threshold.
    static let milestoneRewards: [Reward] = [
        Reward(id: "profile_boost",       name: "Profile Visibility Boost",   xpThreshold: 100,   description: "Your profile is surfaced more often in Quest Mode"),
        Reward(id: "custom_vibe",         name: "Custom Vibe Tag",            xpThreshold: 300,   description: "Create one custom intentVibe tag"),
        Reward(id: "extended_radius",     name: "Extended Quest Radius",      xpThreshold: 600,   description: "Quest Mode scans 0.5 mi instead of 0.25 mi"),
        Reward(id: "priority_queue",      name: "Priority Match Queue",       xpThreshold: 1000,  description: "Your alerts are delivered first in dense areas"),
        Reward(id: "event_invite",        name: "Exclusive Event Invite",     xpThreshold: 2000,  description: "Invitation to local Serendipity meetup events"),
        Reward(id: "verified_priority",   name: "Verified Priority",          xpThreshold: 5000,  description: "Gold-tier visibility + priority in all queues"),
    ]

    /// Returns all milestone rewards the user has unlocked based on current XP.
    /// Detection only — does not grant or persist anything.
    func checkAndUnlockRewards(currentXP: Int) -> [Reward] {
        return Self.milestoneRewards.filter { $0.xpThreshold <= currentXP }
    }

    /// Returns milestone rewards the user has NOT yet unlocked, for UI display.
    func upcomingRewards(currentXP: Int) -> [Reward] {
        return Self.milestoneRewards.filter { $0.xpThreshold > currentXP }
    }

    /// Returns the next reward the user is working toward, or nil if all unlocked.
    func nextReward(currentXP: Int) -> Reward? {
        return Self.milestoneRewards.first { $0.xpThreshold > currentXP }
    }

    // MARK: - Private

    /// Internal helper for all XP grants. Routes through FirestoreService.grantXP
    /// transaction and updates the local cache on success.
    private func grantXP(amount: Int, reason: String) async {
        guard let uid = Auth.auth().currentUser?.uid else { return }

        do {
            let newTotal = try await firestoreService.grantXP(
                uid: uid,
                amount: amount,
                reason: reason
            )

            // Update local cache
            currentGamification?.totalXP = newTotal
            currentGamification?.recacheLevel()

            analytics.logXPAwarded(amount: amount, multiplier: 1.0, reason: reason)
        } catch {
            print("[XPManager] XP grant failed (\(reason)): \(error.localizedDescription)")
        }
    }
}
