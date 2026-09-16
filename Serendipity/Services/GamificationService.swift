// MARK: - SECURITY CHECKLIST COMPLIANCE (see docs/SECURITY_CHECKLIST.md)
// [x] No hardcoded secrets, API keys, or tokens
// [x] XP and badge grants go through the awardXP / awardBadge Cloud Functions.
//     This file performs NO Firestore writes — the `db` handle is gone, so a
//     cross-user write is not expressible here, not merely denied at runtime.
// [x] No method here takes a recipient uid. The function always writes
//     request.auth.uid, so the client cannot name someone else.
// [x] The client sends a reason, not an amount. Amounts live in a server-side
//     table; the multiplier is derived server-side from the user's own profile
//     and their campus ratio, never sent from here.
// [x] Amount clamping (1…10000) and the multiplier bounds (1.0–2.0) are enforced
//     in gamification.ts. The client-side Remote Config values that remain are
//     used only for display copy, not to decide a grant.
// [x] Referral and waitlist-survivor rewards have no client path at all — they
//     are issued by activateWaitlistedUsers on a server-observed event
// [x] No PII logged — only badge names and reason strings
// [x] Badge definitions are read-only constants — no user-controlled badge creation

import Foundation
import Combine
import FirebaseRemoteConfig
import FirebaseFunctions

// MARK: - GamificationService

@MainActor
final class GamificationService: ObservableObject {
    static let shared = GamificationService()

    @Published var activeMultiplier: Double = 1.0
    @Published var recentBadge: BadgeDefinition?

    private let remoteConfig = RemoteConfig.remoteConfig()
    private let functions = Functions.functions()
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

        // No `toFirestoreData()` any more. The badge document is written by
        // `gamification.ts` inside the same transaction that dedupes it; a
        // client-side serializer for a write path that no longer exists is a
        // trap for whoever finds it next. `id` is the only field that crosses
        // the wire — the server owns the rest.
    }

    // MARK: - XP Constants

    // XP amounts intentionally live in `gamification.ts` and nowhere else. A
    // client-side copy of the table is a copy that drifts, and the value it
    // holds is not the one that gets written.

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
            _ = try? await remoteConfig.fetchAndActivate()
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

    /// Grants XP to **the signed-in user**, via the `awardXP` Cloud Function.
    ///
    /// There is deliberately no `uid` parameter. The previous version took one
    /// and wrote `users/{uid}` directly, which meant any client could credit any
    /// account; `firestore.rules` now denies that, and removing the parameter
    /// means the mistake cannot be made again at a call site.
    ///
    /// There is deliberately no `amount` parameter either. The reason selects
    /// the amount from a server-side table, so a caller cannot pass the wrong
    /// number and an attacker cannot pass a large one.
    ///
    /// - Parameter reason: one of the reasons `gamification.ts` accepts from a
    ///   client. An unknown reason is rejected server-side.
    @discardableResult
    func awardXP(reason: XPReason) async -> Int? {
        do {
            let result = try await functions
                .httpsCallable("awardXP")
                .call(["reason": reason.rawValue])

            let payload = result.data as? [String: Any]
            let awarded = payload?["awarded"] as? Int ?? 0

            // The multiplier is applied server-side; log 1.0 rather than
            // guessing at what the server used.
            analytics.logXPAwarded(amount: awarded, multiplier: 1.0, reason: reason.rawValue)
            return payload?["totalXP"] as? Int
        } catch {
            Log.gamification.error("XP award failed (\(reason.rawValue)): \(error.localizedDescription)")
            return nil
        }
    }

    /// Reasons a client may request for itself. Mirrors the allowlist in
    /// `gamification.ts`; anything not here is refused server-side.
    ///
    /// `waitlist_survived` and `referral_reward` are absent on purpose — those
    /// are server-issued and have no client entry point.
    enum XPReason: String {
        case verification
        case firstConnection = "first_connection"
        case icebreakerCompleted = "icebreaker_completed"
        case nameDropCompleted = "namedrop_completed"
    }

    // MARK: - Badge Awarding

    /// Awards a badge to **the signed-in user**, via the `awardBadge` Cloud
    /// Function. Deduplication by badge id happens server-side, inside the same
    /// transaction as the write.
    ///
    /// As with `awardXP`, no recipient parameter exists.
    func awardBadge(_ badge: BadgeDefinition, trigger: String) async {
        do {
            let result = try await functions
                .httpsCallable("awardBadge")
                .call(["badgeId": badge.id])

            let awarded = (result.data as? [String: Any])?["awarded"] as? Bool ?? false
            if awarded {
                recentBadge = badge
                analytics.logBadgeAwarded(badgeName: badge.name, trigger: trigger)
            }
        } catch {
            Log.gamification.error("Badge award failed: \(error.localizedDescription)")
        }
    }

    // MARK: - Reward Actions
    //
    // All self-service. Each one grants to the signed-in user; none can name a
    // recipient, because the underlying calls no longer accept one.

    /// Call after verification completes successfully.
    func rewardVerification() async {
        await awardXP(reason: .verification)
        await awardBadge(BadgeType.verifiedPioneer, trigger: "verification_completed")
    }

    /// Call after first real-world connection.
    func rewardFirstConnection() async {
        await awardXP(reason: .firstConnection)
        await awardBadge(BadgeType.firstConnection, trigger: "first_connection")
    }

    /// Call after completing an icebreaker challenge.
    func rewardIcebreakerCompleted() async {
        await awardXP(reason: .icebreakerCompleted)
    }

    /// Call after 5 successful vibe-matched connections.
    func rewardVibeMatchmaker() async {
        await awardBadge(BadgeType.vibeMatchmaker, trigger: "five_vibe_matches")
    }

    // MARK: - Server-Issued Rewards
    //
    // `waitlist_survivor` and `balance_guardian` badges, and the waitlist and
    // referral XP, are issued by `activateWaitlistedUsers` in the backend. There
    // are deliberately no client methods for them:
    //
    // - Waitlist activation is a scheduled server event. The client is not
    //   present when it happens and has nothing to contribute to the decision.
    // - A referral reward credits *someone else's* account. Any client path to
    //   that is a free XP faucet, however it is dressed up — a callable that
    //   takes a referrer uid is no safer than the direct write it replaced.
    //
    // The client learns about both by re-reading its own profile.
}
