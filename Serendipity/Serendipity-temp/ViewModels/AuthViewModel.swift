import UIKit
import Foundation
import Combine
import FirebaseCore
import FirebaseAuth
import LocalAuthentication
import GoogleSignIn

// MARK: - App State

enum AppState: Equatable {
    case loading
    case unauthenticated
    case onboarding
    case authenticated
}

// MARK: - AuthViewModel

@MainActor
final class AuthViewModel: ObservableObject {
    @Published var appState: AppState = .loading
    @Published var currentUser: UserProfile?
    @Published var isLoading = false
    @Published var errorMessage: String?

    private var authStateHandle: AuthStateDidChangeListenerHandle?
    private var cancellables = Set<AnyCancellable>()

    init() {
        listenToAuthState()
    }

    deinit {
        if let handle = authStateHandle {
            Auth.auth().removeStateDidChangeListener(handle)
        }
    }

    // MARK: - Auth State

    private func listenToAuthState() {
        guard FirebaseApp.app() != nil else {
            // Firebase not configured (no GoogleService-Info.plist) — skip auth
            appState = .unauthenticated
            return
        }
        authStateHandle = Auth.auth().addStateDidChangeListener { [weak self] _, firebaseUser in
            guard let self else { return }
            Task {
                if let firebaseUser {
                    await self.createOrFetchUserProfile(for: firebaseUser)
                } else {
                    self.appState = .unauthenticated
                    self.currentUser = nil
                }
            }
        }
    }

    // MARK: - Profile Loading

    /// Fetches an existing profile or creates a minimal one for new users.
    private func createOrFetchUserProfile(for firebaseUser: FirebaseAuth.User, retryCount: Int = 0) async {
        do {
            if let existing = try await FirestoreService.shared.fetchUser(uid: firebaseUser.uid) {
                self.currentUser = existing
                self.appState = existing.isProfileComplete ? .authenticated : .onboarding
            } else {
                let newProfile = makeMinimalProfile(for: firebaseUser)
                try await FirestoreService.shared.createOrUpdateUser(newProfile)
                self.currentUser = newProfile
                self.appState = .onboarding
            }
        } catch {
            if retryCount < 2 {
                try? await Task.sleep(nanoseconds: UInt64((retryCount + 1)) * 1_000_000_000)
                await createOrFetchUserProfile(for: firebaseUser, retryCount: retryCount + 1)
            } else {
                self.errorMessage = "Unable to load your profile. Please check your connection and try again."
                self.appState = .unauthenticated
            }
        }
    }

    /// Creates a minimal profile with safe defaults for new users.
    private func makeMinimalProfile(for firebaseUser: FirebaseAuth.User) -> UserProfile {
        UserProfile(
            id: firebaseUser.uid,
            uid: firebaseUser.uid,
            displayName: firebaseUser.displayName ?? "",
            age: 0,
            bio: "",
            photoURLs: [],
            selfDescriptors: [],
            verificationStatus: .unverified,
            trustLevel: .bronze,
            preferences: MatchPreferences(
                ageRange: 18...99,
                maxDistanceMiles: 0.25,
                relationshipTypes: [],
                genderPreferences: [],
                interests: [],
                dealbreakers: [],
                compatibilityThreshold: 0.80
            ),
            privacySettings: PrivacySettings(
                questModeEnabled: false,
                visibilityRadius: 0.25,
                autoPauseZones: [],
                alertLimit: 10,
                locationSharingMode: .anonymized,
                showInCommunityEvents: false
            ),
            gamification: GamificationProfile(
                level: 1, xp: 0, badges: [],
                questsCompleted: 0, totalConnections: 0
            ),
            isProfileComplete: false,
            trustScore: 0.5,
            createdAt: Date(),
            lastActive: Date()
        )
    }

    // MARK: - Sign Up

    func signUp(email: String, password: String) async {
        guard FirebaseApp.app() != nil else {
            errorMessage = "Firebase is not configured. Check GoogleService-Info.plist."
            return
        }
        isLoading = true
        defer { isLoading = false }
        do {
            let result = try await Auth.auth().createUser(withEmail: email, password: password)
            await createOrFetchUserProfile(for: result.user)
        } catch {
            errorMessage = "Account creation failed. Please try again."
        }
    }

    // MARK: - Sign In

    func signIn(email: String, password: String) async {
        guard FirebaseApp.app() != nil else {
            errorMessage = "Firebase is not configured. Check GoogleService-Info.plist."
            return
        }
        isLoading = true
        defer { isLoading = false }
        do {
            _ = try await Auth.auth().signIn(withEmail: email, password: password)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    // MARK: - Biometric Auth (Face ID)

    func authenticateWithBiometrics() async -> Bool {
        let context = LAContext()
        var error: NSError?
        guard context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: &error) else {
            errorMessage = error?.localizedDescription ?? "Biometrics unavailable"
            return false
        }
        do {
            let success = try await context.evaluatePolicy(
                .deviceOwnerAuthenticationWithBiometrics,
                localizedReason: "Verify it's you to enter Serendipity"
            )
            return success
        } catch {
            errorMessage = error.localizedDescription
            return false
        }
    }

    // MARK: - Sign Out

    func signOut() {
        do {
            try Auth.auth().signOut()
            appState = .unauthenticated
            currentUser = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    // MARK: - Delete Account

    func deleteAccount() async {
        guard let user = Auth.auth().currentUser else {
            errorMessage = "No user is currently signed in."
            return
        }
        isLoading = true
        defer { isLoading = false }
        do {
            // Delete user data from Firestore and Storage first
            try await FirestoreService.shared.deleteUserData(uid: user.uid)
            // Delete the Firebase Auth account
            try await user.delete()
            currentUser = nil
            appState = .unauthenticated
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    // MARK: - OAuth (Apple / Google) — Stubs

    func signInWithApple() async {
        // TODO: Implement ASAuthorizationAppleIDProvider flow
    }

    func signInWithGoogle() async {
        guard FirebaseApp.app() != nil else {
            errorMessage = "Firebase is not configured. Check GoogleService-Info.plist."
            return
        }
        guard let clientID = FirebaseApp.app()?.options.clientID else {
            errorMessage = "Missing Google client ID in Firebase config."
            return
        }
        guard let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
              let rootVC = windowScene.windows.first?.rootViewController else {
            errorMessage = "Unable to find root view controller."
            return
        }

        isLoading = true
        defer { isLoading = false }

        do {
            let config = GIDConfiguration(clientID: clientID)
            GIDSignIn.sharedInstance.configuration = config
            let result = try await GIDSignIn.sharedInstance.signIn(withPresenting: rootVC)

            guard let idToken = result.user.idToken?.tokenString else {
                errorMessage = "Authentication could not be completed. Please try again."
                return
            }
            let credential = GoogleAuthProvider.credential(
                withIDToken: idToken,
                accessToken: result.user.accessToken.tokenString
            )
            let authResult = try await Auth.auth().signIn(with: credential)
            await createOrFetchUserProfile(for: authResult.user)
        } catch {
            errorMessage = "Sign-in could not be completed. Please try again."
        }
    }
}
