// MARK: - SECURITY CHECKLIST COMPLIANCE (see docs/SECURITY_CHECKLIST.md)
// [x] No hardcoded secrets, API keys, or tokens
// [x] This manager performs NO writes. Referral rewards credit someone else's
//     account, so they are issued by activateWaitlistedUsers on a server-observed
//     event — there is no client path to them, and no method here takes a
//     referrer uid to reward.
// [x] It reads only referrals/{ownUID}, which firestore.rules makes owner-read.
//     The previous version also read users/{referrerUID} to look up their gender;
//     that read is both denied by the rules and unnecessary, since the multiplier
//     is now derived server-side.
// [x] No raw UIDs in analytics — hashed before logging
// [x] Reward amounts and multipliers are clamped in gamification.ts
// [x] No PII logged — only the fact of a read failing
// [x] Referral code generation deferred to server (Cloud Function) — not client-generated

import Foundation
import Combine
import FirebaseAuth
import FirebaseFirestore

// MARK: - ReferralManager

@MainActor
final class ReferralManager: ObservableObject {
    static let shared = ReferralManager()

    @Published var referralCode: String?
    @Published var referralCount: Int = 0
    @Published var pendingRewards: Int = 0

    private let db = Firestore.firestore()
    private let analytics = AnalyticsService.shared

    // No `baseReferralXP` here any more: the amount lives in gamification.ts,
    // which is the only thing that can actually award it.

    private init() {}

    // MARK: - Fetch Referral Code

    /// Fetches the caller's own referral code from Firestore.
    ///
    /// Private, and takes no uid from outside: `referrals/{uid}` is owner-read by
    /// rule, so a call with anyone else's uid could only ever fail. Exposing the
    /// parameter would advertise a read that does not exist.
    private func fetchReferralCode(uid: String) async {
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

    // MARK: - Referral Rewards (server-issued)
    //
    // There is deliberately no method here that rewards a referrer.
    //
    // The old `processReferralReward(referrerUID:referrerGender:)` awarded XP by
    // writing the *referrer's* user document from the referred user's device.
    // `firestore.rules` denies that now, and correctly: a client that can credit
    // another account is a free XP faucet, and wrapping the same call in a
    // callable that accepts a referrer uid would be no better.
    //
    // The reward is issued by `activateWaitlistedUsers` (functions/src/onUserSignup.ts),
    // which calls `grantWaitlistActivationRewards`. Activation is a scheduled
    // server event: the server knows who was activated and who referred them, and
    // the client is not present and has nothing to add.
    //
    // The client's only job is to notice. Refreshing the profile picks up the new
    // XP and badge like any other server-side change.

    /// Re-reads the caller's own referral document after a server-side reward.
    ///
    /// Owner-read only. There is no way to observe anyone else's referral state.
    func refreshOwnReferralState() async {
        guard let uid = Auth.auth().currentUser?.uid else { return }
        await fetchReferralCode(uid: uid)
    }

    // MARK: - Weekend/Weekday Tracking

    /// Logs activation timing for weekday vs weekend analysis.
    func logActivationTiming(activationCount: Int) {
        let calendar = Calendar.current
        let isWeekend = calendar.isDateInWeekend(Date())
        analytics.logWeekdayVsWeekendActivation(isWeekend: isWeekend, activationCount: activationCount)
    }
}
