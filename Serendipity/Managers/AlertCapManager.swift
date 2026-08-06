// MARK: - SECURITY CHECKLIST COMPLIANCE (see docs/SECURITY_CHECKLIST.md)
// [x] No hardcoded secrets, API keys, or tokens
// [x] Client-side daily alert caps are ADVISORY ONLY — final enforcement happens
//     via Firestore Security Rules (to be added in follow-up)
// [x] Firestore writes use updateData with ONLY alert-related fields — never
//     overwrites server-authoritative fields (accountStatus, trustLevel, etc.)
// [x] Document ID comes from @DocumentID (Firestore-assigned); uid is non-optional
// [x] No PII logged — only uid passed to error context, no partner data exposed
// [x] Profile loaded via FirestoreService where possible + date reset guard
// [x] Directly addresses POTENTIAL_ISSUES.md #1 (Gender Imbalance) and
//     docs/LAUNCH_STRATEGY.md (campus/nightlife/festival launches)

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

    /// Check if the current user can send an alert right now (uses cached profile)
    func canSendAlert() async -> Bool {
        guard var profile = currentUserProfile else { return false }
        return profile.canSendAlert()
    }

    /// Record that an alert was sent (call after successful match alert)
    func recordAlertSent() async {
        guard var profile = currentUserProfile else { return }
        profile.incrementAlertCount()
        currentUserProfile = profile
        await updateAlertFieldsInFirestore(profile)
    }

    /// Get the user's current daily limit (for UI display)
    func getCurrentDailyLimit() -> Int {
        currentUserProfile?.currentDailyLimit ?? 30
    }

    // MARK: - MatchManager Integration API

    /// Updates the cached user profile used for cap enforcement.
    /// Call from MatchManager.enableQuestMode to sync caps on session start.
    func updateUserCaps(for user: UserProfile) {
        currentUserProfile = user
    }

    /// Checks whether `user` can send an alert for the given `match`.
    /// Resets daily counter if the date has rolled over.
    /// This is a client-side courtesy gate — Firestore rules are authoritative.
    func canSendAlert(for user: UserProfile, match: Match?) -> Bool {
        // Sync latest profile state
        currentUserProfile = user
        guard var profile = currentUserProfile else { return false }
        return profile.canSendAlert()
    }

    /// Returns the asymmetric daily alert cap for a given gender.
    func dailyCapForGender(_ gender: Gender) -> Int {
        switch gender {
        case .female:         return 10
        case .nonBinary:      return 20
        case .preferNotToSay: return 15
        case .male:           return 40
        }
    }

    /// Records an alert sent by the user for a specific match.
    /// Increments the daily counter and syncs advisory state to Firestore.
    func recordAlertSent(for uid: String, matchID: String) async {
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
                Log.alertCaps.error("No profile found for uid: \(uid)")
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