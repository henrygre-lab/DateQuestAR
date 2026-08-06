// MARK: - SECURITY CHECKLIST COMPLIANCE (see docs/SECURITY_CHECKLIST.md)
// [x] No hardcoded secrets, API keys, or tokens
// [x] Referral validation done server-side via Cloud Functions — client only reads results
// [x] No raw UIDs in analytics — hashed before logging
// [x] Reward multipliers clamped to prevent exploitation (max 3.0x)
// [x] No PII logged — only gender, multiplier, and XP amounts
// [x] Referral code generation deferred to server (Cloud Function) — not client-generated

import Foundation
import Combine
import FirebaseFirestore
import FirebaseFunctions

// MARK: - ReferralManager

@MainActor
final class ReferralManager: ObservableObject {
    static let shared = ReferralManager()

    @Published var referralCode: String?
    @Published var referralCount: Int = 0
    @Published var pendingRewards: Int = 0

    private let db = Firestore.firestore()
    private let functions = Functions.functions()
    private let analytics = AnalyticsService.shared
    private let gamification = GamificationService.shared

    /// Base XP reward for a successful referral.
    private let baseReferralXP = 100

    private init() {}

    // MARK: - Fetch Referral Code

    /// Fetches the user's referral code from Firestore.
    /// The code is generated server-side by a Cloud Function on account creation.
    func fetchReferralCode(uid: String) async {
        do {
            let doc = try await db.collection("referrals").document(uid).getDocument()
            if let code = doc.data()?["code"] as? String {
                referralCode = code
                referralCount = doc.data()?["successfulReferrals"] as? Int ?? 0
            }
        } catch {
            Log.referral.error("Failed to fetch referral code: \(error.localizedDescription)")
        }
    }

    // MARK: - Process Referral Reward

    /// Called when a referred user completes activation (server notifies client).
    /// Awards gender-weighted XP to the referrer.
    func processReferralReward(referrerUID: String, referrerGender: Gender) async {
        let needsBoost = BalanceEnforcer.shared.needsFemaleBoost
        var multiplier = 1.0

        // Gender-weighted rewards: underrepresented gender gets boosted referral XP
        if (referrerGender == .female || referrerGender == .nonBinary) && needsBoost {
            multiplier = min(gamification.femaleAcquisitionBoost(), 3.0)
        }

        let xpAmount = Int(Double(baseReferralXP) * multiplier)

        await gamification.awardXP(
            uid: referrerUID,
            baseAmount: xpAmount,
            reason: "referral_reward"
        )

        analytics.logReferralCompleted(
            referrerGender: referrerGender,
            rewardMultiplier: multiplier,
            xpAwarded: xpAmount
        )

        referralCount += 1
    }

    // MARK: - Waitlist Activation Bonus

    /// Awards bonus XP when a referred user activates from the waitlist.
    /// Tracks referral source for analytics.
    func processWaitlistActivationBonus(
        activatedUID: String,
        activatedGender: Gender,
        referrerUID: String?,
        waitHours: Double
    ) async {
        // Log the waitlist activation event
        analytics.logWaitlistActivation(waitHours: waitHours, gender: activatedGender)

        // Award waitlist survivor reward to the activated user
        await gamification.rewardWaitlistSurvivor(uid: activatedUID, gender: activatedGender)

        // If referred, give the referrer a bonus
        if let referrerUID = referrerUID {
            do {
                let referrerDoc = try await db.collection("users").document(referrerUID).getDocument()
                let referrerGenderRaw = referrerDoc.data()?["gender"] as? String ?? "prefer_not_to_say"
                let referrerGender = Gender(rawValue: referrerGenderRaw) ?? .preferNotToSay

                await processReferralReward(referrerUID: referrerUID, referrerGender: referrerGender)
            } catch {
                Log.referral.error("Failed to fetch referrer profile: \(error.localizedDescription)")
            }
        }
    }

    // MARK: - Weekend/Weekday Tracking

    /// Logs activation timing for weekday vs weekend analysis.
    func logActivationTiming(activationCount: Int) {
        let calendar = Calendar.current
        let isWeekend = calendar.isDateInWeekend(Date())
        analytics.logWeekdayVsWeekendActivation(isWeekend: isWeekend, activationCount: activationCount)
    }
}
