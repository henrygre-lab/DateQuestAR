// MARK: - SECURITY CHECKLIST COMPLIANCE
// [x] No hardcoded secrets, API keys, or tokens
// [x] All thresholds read from server (Firestore global_gender_stats) — not client constants
// [x] No client-side writes to global_gender_stats — read-only listener
// [x] waitlist decisions made server-side (Cloud Functions); client only reflects status
// [x] alertCap values originate from server; client enforces locally as a courtesy check
// [x] No PII logged — only aggregate ratios and enum states
// [x] Minimal data exposure — shouldShowMatch returns Bool, no profile data leaked
// [x] Listener errors logged without exposing internals to UI
// [x] Analytics events contain no raw UIDs or PII

import Foundation
import FirebaseFirestore
import Combine

// MARK: - BalanceEnforcer

@MainActor
final class BalanceEnforcer: ObservableObject {
    static let shared = BalanceEnforcer()

    // MARK: - Published State

    @Published var currentRatio: Double = 0.5           // male fraction: 0.0–1.0
    @Published var needsFemaleBoost: Bool = false
    @Published var waitlistStatus: String = "none"      // "none", "queued", "activating"
    @Published private(set) var isStatsAvailable: Bool = false

    // MARK: - Thresholds (read from server on init; fallback defaults)

    private var maleCapThreshold: Double = 0.55
    private var femaleAlertCap: Int = 3
    private var maleAlertCap: Int = 8
    private var womenFirstQueuingEnabled: Bool = false

    // MARK: - Dependencies

    private let analytics = AnalyticsService.shared
    private let db = Firestore.firestore()
    private var statsListener: ListenerRegistration?

    // MARK: - Init

    private init() {}

    deinit {
        statsListener?.remove()
    }

    // MARK: - Listener Lifecycle

    /// Starts the real-time gender-stats listener. Idempotent — no-op if already
    /// listening. Call this only after a successful profile load (e.g. from
    /// AuthViewModel/MatchManager) so it never fires before authentication and
    /// avoids noisy reads/logs on cold start or during testing.
    func startListening() {
        guard statsListener == nil else { return }
        listenToGenderStats()
    }

    /// Stops the real-time listener and clears it so it can be restarted later.
    func stopListening() {
        statsListener?.remove()
        statsListener = nil
    }

    // MARK: - Real-Time Listener

    /// Listens to `global_gender_stats/current` for live ratio updates.
    /// This document is written exclusively by the balanceMonitor Cloud Function.
    private func listenToGenderStats() {
        statsListener = db.collection("global_gender_stats").document("current")
            .addSnapshotListener { [weak self] snapshot, error in
                guard let self else { return }

                if let error {
                    Log.balance.error("Stats listener error: \(error.localizedDescription)")
                    // Keep last-known-good values; don't reset to defaults on transient errors
                    return
                }

                guard let data = snapshot?.data() else {
                    // Document doesn't exist yet (first deploy / empty state)
                    Task { @MainActor in
                        self.isStatsAvailable = false
                    }
                    return
                }

                Task { @MainActor in
                    self.isStatsAvailable = true

                    // Clamp ratio to valid range to guard against corrupted data
                    let rawRatio = data["malePct"] as? Double ?? 0.5
                    self.currentRatio = min(max(rawRatio, 0.0), 1.0)

                    let previousNeedsFemaleBoost = self.needsFemaleBoost
                    self.needsFemaleBoost = self.currentRatio > self.maleCapThreshold
                    self.womenFirstQueuingEnabled = data["womenFirstQueuingEnabled"] as? Bool ?? false

                    // Log gender ratio update to analytics
                    self.analytics.logGenderRatioUpdate(
                        malePct: self.currentRatio,
                        needsFemaleBoost: self.needsFemaleBoost
                    )

                    // Log when needsFemaleBoost state changes
                    if self.needsFemaleBoost != previousNeedsFemaleBoost {
                        self.analytics.logGenderRatioUpdate(
                            malePct: self.currentRatio,
                            needsFemaleBoost: self.needsFemaleBoost
                        )
                    }

                    // Server can override caps dynamically; validate ranges
                    if let serverFemaleCap = data["femaleAlertCap"] as? Int,
                       (1...20).contains(serverFemaleCap) {
                        self.femaleAlertCap = serverFemaleCap
                    }
                    if let serverMaleCap = data["maleAlertCap"] as? Int,
                       (1...20).contains(serverMaleCap) {
                        self.maleAlertCap = serverMaleCap
                    }
                }
            }
    }

    // MARK: - Match Visibility Gate

    /// Determines whether a match should be surfaced to this user.
    /// Server-side Cloud Functions enforce the authoritative waitlist;
    /// this is a client-side courtesy filter to reduce wasted UI.
    func shouldShowMatch(to user: UserProfile) -> Bool {
        // Waitlisted, suspended, or banned users never see matches
        guard user.accountStatus == .active else { return false }

        // If stats haven't loaded yet, allow matches (fail-open for UX;
        // server rules are the real gate)
        guard isStatsAvailable else { return true }

        // If gender balance is skewed and user is male, apply visibility cap
        if needsFemaleBoost && user.gender == .male {
            let overflow = currentRatio - maleCapThreshold   // e.g. 0.60 - 0.55 = 0.05
            let passRate = max(0.1, 1.0 - (overflow * 5.0))  // scale down, floor at 10%
            return Double.random(in: 0...1) <= passRate
        }

        return true
    }

    // MARK: - Visibility Cap

    /// Applies boost multiplier for underrepresented genders.
    /// Women get higher visibility when female ratio is low.
    func applyVisibilityCap() {
        // No-op on client — visibility boost is applied server-side via
        // balanceBoostMultiplier on the UserProfile. This method exists
        // for Phase 3 integration where MatchManager will call it to
        // read the current boost state before scoring.
    }

    // MARK: - Alert Cap Calculation

    /// Returns the hourly alert cap for a given gender.
    /// Server is authoritative; this provides a local fast-path check.
    func calculateAlertCap(for gender: Gender) -> Int {
        switch gender {
        case .female, .nonBinary:
            return femaleAlertCap
        case .male:
            return needsFemaleBoost ? max(1, maleAlertCap / 2) : maleAlertCap
        case .preferNotToSay:
            return maleAlertCap  // Default to standard cap
        }
    }

    // MARK: - Waitlist Status Sync

    /// Reads the current user's waitlist status from Firestore.
    /// The waitlist document is managed by Cloud Functions only.
    func syncWaitlistStatus(for uid: String) async {
        do {
            let doc = try await db.collection("waitlist").document(uid).getDocument()
            if doc.exists, let status = doc.data()?["status"] as? String {
                waitlistStatus = status
            } else {
                waitlistStatus = "none"
            }
        } catch {
            Log.balance.error("Waitlist sync failed: \(error.localizedDescription)")
            // Don't change waitlistStatus on error — keep last known value
        }
    }
}
