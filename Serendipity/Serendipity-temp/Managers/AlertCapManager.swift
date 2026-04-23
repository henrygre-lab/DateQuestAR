// Serendipity/Managers/AlertCapManager.swift
import Foundation
import FirebaseFirestore
import FirebaseFirestoreSwift

// MARK: - AlertCapManager
// Central manager for asymmetric alert caps and gender balance safety features
// Directly addresses POTENTIAL_ISSUES.md #1: Gender Imbalance / Male Overload

@MainActor
class AlertCapManager: ObservableObject {
    static let shared = AlertCapManager()
    
    @Published var currentUserProfile: UserProfile?
    
    // MARK: - Public API
    
    /// Check if the current user can send an alert right now
    func canSendAlert() async -> Bool {
        guard var profile = currentUserProfile else { return false }
        return profile.canSendAlert()
    }
    
    /// Record that an alert was sent (call after successful match alert)
    func recordAlertSent() async {
        guard var profile = currentUserProfile else { return }
        profile.incrementAlertCount()
        currentUserProfile = profile
        
        // TODO: Sync to Firestore (server-side enforcement later)
        await updateProfileInFirestore(profile)
    }
    
    /// Get the user's current daily limit for UI display
    func getCurrentDailyLimit() -> Int {
        currentUserProfile?.currentDailyLimit ?? 30
    }
    
    // MARK: - Private helpers
    
    private func updateProfileInFirestore(_ profile: UserProfile) async {
        guard let uid = profile.uid, let id = profile.id else { return }
        
        do {
            try await Firestore.firestore()
                .collection("users")
                .document(id)
                .setData(from: profile, merge: true)
        } catch {
            print("Failed to update alert count: \(error)")
        }
    }
    
    // Load current user profile (call from Auth or app launch)
    func loadCurrentUserProfile(uid: String) async {
        print("AlertCapManager: Loading profile for uid: \(uid)")
        // TODO: Implement full load via FirestoreService
    }
}
