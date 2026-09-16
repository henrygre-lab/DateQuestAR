// MARK: - SECURITY CHECKLIST COMPLIANCE (see docs/SECURITY_CHECKLIST.md)
// [x] No hardcoded secrets, API keys, or tokens
// [x] Client-side daily alert caps are ADVISORY ONLY — firestore.rules is the
//     enforcement boundary and rejects any client write to the fields that decide
//     access (trustLevel, accountStatus, activeIntents, datingCooldownUntil)
// [x] Caps apply ONLY to Dating-gated encounters. A Study, Hangout, Friendship or
//     Event overlap is never gender-throttled — callers must pass the session's
//     locked intents, and there is no overload that lets them skip it.
// [x] The Dating decision comes from the session's LOCKED intents, not from either
//     user's current intent list, so switching Dating off mid-session changes
//     nothing about the session in flight
// [x] The 24h Dating-off cooldown is read from datingCooldownUntil, which only
//     setActiveIntents writes — a client cannot shorten or skip it
// [x] Firestore writes use updateData with ONLY alert-related fields — never
//     overwrites server-authoritative fields (accountStatus, trustLevel, etc.)
// [x] Document ID comes from @DocumentID (Firestore-assigned); uid is non-optional
// [x] No PII logged — no uid, no partner data; only doc-prefix on write failure
// [x] Profile loaded via FirestoreService where possible + date reset guard
// [x] Directly addresses POTENTIAL_ISSUES.md #1 (Gender Imbalance) and
//     docs/LAUNCH_STRATEGY.md (campus pilot)

import Foundation
import FirebaseFirestore
import Combine

// MARK: - AlertCapManager
// Central manager for asymmetric alert caps and gender balance safety features
// All alert decisions must go through this manager before any proximity alert is sent.

@MainActor
class AlertCapManager: ObservableObject {
    static let shared = AlertCapManager()

    @Published var currentUserProfile: UserProfile?

    private let firestoreService = FirestoreService.shared

    // MARK: - Public API

    /// Whether the cached user can send an alert on a **Dating-gated** encounter.
    ///
    /// There is no capless variant of this call by design: a caller that does not
    /// know the session's intents cannot be allowed to consult a Dating cap, and
    /// a caller that does know them should pass them.
    func canSendDatingAlert() async -> Bool {
        guard var profile = currentUserProfile else { return false }
        return profile.canSendAlert()
    }

    /// Record that a Dating-gated alert was sent.
    ///
    /// Only Dating alerts consume the daily allowance. Counting a Study alert
    /// against a woman's 10/day would push her out of the intents that are not
    /// gender-imbalanced in the first place.
    func recordDatingAlertSent() async {
        guard var profile = currentUserProfile else { return }
        profile.incrementAlertCount()
        currentUserProfile = profile
        await updateAlertFieldsInFirestore(profile)
    }

    /// The user's Dating daily limit, for UI display.
    ///
    /// Returns nil when Dating is not gated for this user, because there is no
    /// cap to show — a screen that renders "0 of 10" to someone on Study only
    /// would be describing a limit that does not apply to them.
    func currentDatingDailyLimit(at now: Date = Date()) -> Int? {
        guard let profile = currentUserProfile, profile.isDatingGated(at: now) else { return nil }
        return profile.currentDailyLimit
    }

    // MARK: - MatchManager Integration API

    /// Updates the cached user profile used for cap enforcement.
    /// Call from MatchManager.enableQuestMode to sync caps on session start.
    func updateUserCaps(for user: UserProfile) {
        currentUserProfile = user
    }

    /// Checks whether `user` can send an alert for an encounter with the given
    /// locked intents.
    ///
    /// `lockedIntents` is the overlap frozen at session start, not either user's
    /// current list. If it contains no Dating, this returns true without touching
    /// the daily counter at all: the asymmetric caps exist to stop women being
    /// swarmed with romantic attention, and they have no business throttling
    /// someone looking for a study partner.
    ///
    /// Client-side courtesy gate — Firestore rules are authoritative.
    func canSendAlert(for user: UserProfile,
                      match: Match?,
                      lockedIntents: [Intent]) -> Bool {
        currentUserProfile = user
        guard Intent.engagesGenderBalance(lockedIntents) else { return true }
        guard var profile = currentUserProfile else { return false }
        return profile.canSendAlert()
    }

    /// Returns the asymmetric daily alert cap for a given gender.
    ///
    /// Only meaningful for Dating-gated encounters; callers must have established
    /// that before consulting it.
    func dailyCapForGender(_ gender: Gender) -> Int {
        switch gender {
        case .female:         return 10
        case .nonBinary:      return 20
        case .preferNotToSay: return 15
        case .male:           return 40
        }
    }

    /// Records an alert sent by the user for a specific match.
    ///
    /// Increments the daily counter only when the match is Dating-gated. The flag
    /// comes off the match document, which is immutable once written —
    /// `firestore.rules` lists `isDatingGated` among the fields a participant
    /// cannot rewrite, so it cannot be flipped after the fact to dodge a cap.
    func recordAlertSent(for uid: String, match: Match) async {
        guard match.isDatingGated else { return }
        guard var profile = currentUserProfile, profile.uid == uid else { return }
        profile.incrementAlertCount()
        currentUserProfile = profile
        await updateAlertFieldsInFirestore(profile)
    }

    // MARK: - Private

    /// Syncs ONLY alert-related fields to Firestore using updateData.
    /// This is critical for security — never overwrite authoritative fields.
    private func updateAlertFieldsInFirestore(_ profile: UserProfile) async {
        // Prefer the Firestore-assigned @DocumentID; fall back to the non-optional
        // uid, since users are stored at users/{uid} so uid is a valid doc path.
        let documentID = profile.id ?? profile.uid
        guard !documentID.isEmpty else {
            Log.alertCaps.error("Cannot sync alert count: empty document ID (profile.id and uid both unusable)")
            return
        }

        do {
            try await Firestore.firestore()
                .collection("users")
                .document(documentID)
                .updateData([
                    "alertsSentToday": profile.alertsSentToday,
                    "lastAlertResetDate": Timestamp(date: profile.lastAlertResetDate)
                ])
        } catch {
            // Log a short, non-PII doc prefix to aid on-device debugging.
            let idPrefix = String(documentID.prefix(6))
            Log.alertCaps.error("Failed to sync alert count for doc \(idPrefix)…: \(error.localizedDescription)")
            // Advisory only — Firestore Security Rules are the real enforcement
        }
    }

    // MARK: - Load current user (call from AuthViewModel or on app launch)

    /// Loads the current user's profile from FirestoreService and initializes daily cap state.
    /// Resets the daily counter if the date has rolled over since the last fetch.
    func loadCurrentUserProfile(uid: String) async {
        guard !uid.isEmpty else {
            Log.alertCaps.error("Cannot load profile: empty uid")
            return
        }
        do {
            guard let profile = try await firestoreService.fetchUser(uid: uid) else {
                Log.alertCaps.error("No profile found for the current user")
                return
            }

            var mutableProfile = profile
            mutableProfile.resetAlertsIfNeeded()
            currentUserProfile = mutableProfile
        } catch {
            Log.alertCaps.error("Failed to load profile: \(error.localizedDescription)")
        }
    }
}