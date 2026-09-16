// MARK: - SECURITY CHECKLIST COMPLIANCE (see docs/SECURITY_CHECKLIST.md)
// [x] No hardcoded secrets, API keys, or tokens — Firebase config via GoogleService-Info.plist
// [x] Sign-in errors surface generic messages — no account-existence leakage
// [x] App state is derived from server-issued fields only (schoolId,
//     enrollmentStatus, studentIDStatus). A signed-in account with no school
//     lands on .schoolGate; one without a verified student ID lands on
//     .studentIDPending. Neither can be skipped from the client.
// [x] The new profile is created at least-privileged defaults — no schoolId,
//     .unverified, .none, .bronze — which is exactly what firestore.rules
//     requires on create
// [x] Custom claims are refreshed before routing, because firestore.rules reads
//     claims rather than the profile document
// [x] LocalAuthentication (Face ID / Touch ID) is a UI gate only; Firebase session is authoritative
// [x] Google Sign-In token handled entirely by the GoogleSignIn SDK — never stored or logged by app
// [x] Sign-out clears the Keychain-held phone number alongside the session
// [x] Developer Bypass is #if DEBUG only — zero surface area in production builds

import UIKit
import Foundation
import Combine
import FirebaseCore
import FirebaseAuth
import LocalAuthentication
import GoogleSignIn

// MARK: - App State

/// Where the app should be, derived entirely from server-issued state.
///
/// The order matters and is the product's gate order: you cannot reach profile
/// setup without a school, and you cannot reach the app without a student ID.
enum AppState: Equatable {
    case loading
    case unauthenticated

    /// Signed in, but no school issued yet. Phone + allowlisted .edu magic link,
    /// school OAuth, or enrollment proof.
    case schoolGate

    /// Enrollment proof submitted and awaiting review. Grants nothing meanwhile.
    case enrollmentReview

    /// School gate passed; student ID card photo + liveness still outstanding.
    /// The community is visible, Quest Mode is not.
    case studentIDPending

    case onboarding

    /// Queued for **Dating** by the balance tools. Every other intent still works.
    case waitlisted

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

                // firestore.rules reads custom claims, not the profile document.
                // Refreshing here means the state we route to is the state the
                // backend will actually honour.
                await SchoolGateManager.shared.refreshClaims()

                self.appState = Self.route(for: existing)

                // Initialize XP system and record daily login on successful profile load
                await XPManager.shared.loadCurrentUserGamification()
                await XPManager.shared.recordDailyLogin()
            } else {
                let newProfile = makeMinimalProfile(for: firebaseUser)
                try await FirestoreService.shared.createUser(newProfile)
                self.currentUser = newProfile
                // A brand-new account has no school, so it starts at the gate —
                // never at onboarding.
                self.appState = .schoolGate
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

    /// Maps a profile to the screen it belongs on.
    ///
    /// Every branch reads a server-owned field. There is deliberately no
    /// "close enough" case: an account that is missing a gate is sent back to
    /// that gate rather than allowed through with reduced function, because the
    /// backend would refuse its reads anyway and the user would see an empty app
    /// with no explanation.
    static func route(for profile: UserProfile) -> AppState {
        guard profile.schoolId?.isEmpty == false else {
            return profile.enrollmentStatus == .pending ? .enrollmentReview : .schoolGate
        }

        guard profile.enrollmentStatus.grantsCommunityAccess else {
            // Alumni and revoked accounts have lost their community. Sending
            // them to the gate is honest: re-verifying is the only way back.
            return profile.enrollmentStatus == .pending ? .enrollmentReview : .schoolGate
        }

        guard profile.studentIDStatus.isIDVerified else { return .studentIDPending }
        guard profile.isProfileComplete else { return .onboarding }
        guard profile.accountStatus != .waitlisted else { return .waitlisted }
        return .authenticated
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
            gamification: GamificationProfile(),
            isProfileComplete: false,
            trustScore: 0.5,
            createdAt: Date(),
            lastActive: Date(),
            // Least-privileged defaults, spelled out rather than inherited so
            // it is obvious at a glance that a new account grants nothing.
            // firestore.rules requires exactly these values on create.
            schoolId: nil,
            schoolDisplayName: nil,
            enrollmentStatus: .unverified,
            studentIDStatus: .none,
            // Hangout + Study. Dating is opt-in and needs the face match.
            activeIntents: Intent.defaults
        )
    }

    /// Re-reads the profile and re-routes.
    ///
    /// Called after a Cloud Function has changed something the client cannot
    /// write — a school issued, a student ID verified. The claim refresh matters
    /// as much as the read: `firestore.rules` decides on claims, so routing on a
    /// fresh profile with a stale token would land the user on a screen whose
    /// queries then fail.
    func reloadProfile() async {
        guard let uid = Auth.auth().currentUser?.uid else { return }
        await SchoolGateManager.shared.refreshClaims()
        guard let profile = try? await FirestoreService.shared.fetchUser(uid: uid) else { return }
        currentUser = profile
        appState = Self.route(for: profile)
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
            // Checklist §02: never let a sign-in flow leak whether an account
            // exists. Firebase's `localizedDescription` distinguishes
            // `.userNotFound` ("no user record corresponding to this
            // identifier") from `.wrongPassword` ("the password is invalid"),
            // which turns the login form into an account-enumeration oracle:
            // an attacker learns which addresses are registered on this app
            // without ever signing in. One message covers both.
            errorMessage = "Incorrect email or password."
            Log.app.error("Sign-in failed: \(error.localizedDescription)")
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
        #if DEBUG
        // Tear down any demo walkthrough state so mock data never outlives the session.
        MatchManager.shared.endDemoEncounter()
        #endif
        do {
            try Auth.auth().signOut()
            // The phone number lives in Keychain, not UserDefaults, and it
            // belongs to a session that no longer exists.
            SchoolGateManager.shared.clearLocalIdentity()
            appState = .unauthenticated
            currentUser = nil
        } catch {
            errorMessage = "Could not sign out. Please try again."
            Log.app.error("Sign-out failed: \(error.localizedDescription)")
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
            // §02: no raw backend error text in the UI. `requiresRecentLogin`
            // is the one case the user can actually act on, so it earns its own
            // message; everything else is a generic failure with the detail in
            // the log.
            if (error as NSError).code == AuthErrorCode.requiresRecentLogin.rawValue {
                errorMessage = "For your security, please sign in again before deleting your account."
            } else {
                errorMessage = "Could not delete your account. Please try again."
            }
            Log.app.error("Account deletion failed: \(error.localizedDescription)")
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
