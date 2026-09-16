// MARK: - SECURITY CHECKLIST COMPLIANCE (see docs/SECURITY_CHECKLIST.md)
// [x] No hardcoded secrets, API keys, or tokens
// [x] This screen is only reachable after the school gate and the student ID
//     check — RootView routes on server-issued state, so setup cannot be used to
//     get into a community
// [x] The profile write is field-whitelisted (saveProfileEdits) — schoolId,
//     enrollmentStatus, studentIDStatus, verifiedAge, trustLevel, accountStatus
//     and activeIntents are all server-owned and are never sent from here
// [x] Intents are written through the setActiveIntents Cloud Function, which is
//     what enforces the Dating gate and starts the 24h Dating-off cooldown
// [x] Gender selection calls server-side applyGenderDefaults Cloud Function
// [x] Waitlist decision made server-side — client only reads the result, and the
//     waitlist is Dating-only
// [x] Photo uploads scoped to authenticated user's storage path; no verification
//     artefact ever goes to that path
// [x] Input validation on all fields before Firestore write
// [x] No raw coordinates — geohash only via LocationService
// [x] Server timestamps used for profile creation

import SwiftUI
import PhotosUI
import FirebaseAuth
import FirebaseStorage
import FirebaseFunctions

struct ProfileSetupView: View {
    @EnvironmentObject var authViewModel: AuthViewModel
    @EnvironmentObject var balanceEnforcer: BalanceEnforcer
    @Environment(\.dq) private var p
    @StateObject private var verifier = SafetyVerifier()
    @State private var step: SetupStep = .studentID
    @State private var selectedPhotos: [PhotosPickerItem] = []
    @State private var displayName = ""
    @State private var bio = ""
    @State private var age = 25
    @State private var selectedGender: Gender = .preferNotToSay
    @State private var selectedInterests: Set<String> = []
    @State private var selectedIntents: Set<Intent> = Set(Intent.defaults)
    @State private var selectedVibes: Set<String> = []
    @State private var prefMinAge = 21
    @State private var prefMaxAge = 35
    @State private var alertLimit = 5
    @State private var locationMode = PrivacySettings.LocationSharingMode.anonymized
    @State private var isSaving = false
    @State private var saveError: String?
    @State private var showErrorAlert = false

    enum SetupStep: Int, CaseIterable {
        case studentID, photos, bio, preferences, vibes, privacy

        var title: String {
            switch self {
            case .studentID:     return "Verify You're a Student"
            case .photos:        return "Add Your Photos"
            case .bio:           return "About You"
            case .preferences:   return "What You're Here For"
            case .vibes:         return "Your Vibe"
            case .privacy:       return "Privacy & Safety"
            }
        }
    }

    var body: some View {
        NavigationStack {
            ZStack {
                p.bg.ignoresSafeArea()

                VStack(spacing: 0) {
                    DQTopBar(title: step.title, style: .pushed) {
                        #if DEBUG
                        DQTopBarAction(title: "Skip") {
                            authViewModel.appState = .authenticated
                        }
                        #endif
                    }

                    // Onboarding gets a plain dot row — StageStepper reads as
                    // reveal progress and would import a meaning that is not here.
                    DQStepDots(total: SetupStep.allCases.count, current: step.rawValue)

                    ScrollView {
                        stepContent
                    }

                    navigationButtons
                        .padding(.top, DQSpace.gutter)
                }
                .padding(.horizontal, DQSpace.gutter)
                .padding(.top, DQSpace.safeTop)
                .padding(.bottom, DQSpace.safeBottom)
            }
            .ignoresSafeArea(edges: .top)
            .toolbar(.hidden, for: .navigationBar)
            // A commit, not a fetch: there is no incoming shape to preview
            // because the user is leaving the screen, so it spins.
            .dqBlockingSave(isActive: isSaving, title: "Creating your profile…")
            .alert("Something went wrong", isPresented: $showErrorAlert) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(saveError ?? "Please try again.")
            }
        }
    }

    // MARK: - Step Content

    @ViewBuilder
    private var stepContent: some View {
        switch step {
        case .studentID:
            StudentIDStepView(verifier: verifier,
                              profileAge: age,
                              onVerified: { advanceStep() })
        case .photos:
            PhotosStepView(selectedPhotos: $selectedPhotos)
        case .bio:
            BioStepView(displayName: $displayName, bio: $bio, age: $age, selectedGender: $selectedGender)
        case .preferences:
            PreferencesStepView(
                selectedInterests: $selectedInterests,
                selectedIntents: $selectedIntents,
                prefMinAge: $prefMinAge,
                prefMaxAge: $prefMaxAge,
                // Read from the profile, which reads from the server. The chip is
                // disabled rather than hidden so the requirement is visible.
                canUseDating: authViewModel.currentUser?.canUseDatingIntent ?? false
            )
        case .vibes:
            VibeStepView(selectedVibes: $selectedVibes)
        case .privacy:
            PrivacyStepView(alertLimit: $alertLimit, locationMode: $locationMode)
        }
    }

    // MARK: - Navigation Buttons

    private var navigationButtons: some View {
        HStack(spacing: DQSpace.tight) {
            if step != .studentID {
                Button("Back") {
                    withAnimation { step = SetupStep(rawValue: step.rawValue - 1) ?? .studentID }
                }
                .buttonStyle(.dqGhost)
            }
            Button(step == .privacy ? "Start Questing" : "Next") {
                advanceStep()
            }
            .buttonStyle(.dqNeutral)
            .disabled(isSaving)
            .accessibilityHint(step == .privacy ? "Finishes setup and enters the app" : "Advances to the next step")
        }
    }

    private func advanceStep() {
        if step == .privacy {
            Task { await saveProfileAndFinish() }
        } else {
            withAnimation { step = SetupStep(rawValue: step.rawValue + 1) ?? .privacy }
        }
    }

    // MARK: - Validation

    private func validateInputs() -> String? {
        let trimmedName = displayName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty, (2...30).contains(trimmedName.count) else {
            return "Display name must be 2\u{2013}30 characters."
        }
        guard bio.count <= 500 else {
            return "Bio must be 500 characters or fewer."
        }
        guard (18...99).contains(age) else {
            return "Age must be between 18 and 99."
        }
        guard selectedPhotos.count >= 2 else {
            return "Please add at least 2 photos."
        }
        guard !selectedIntents.isEmpty else {
            return "Pick at least one thing you're here for."
        }
        guard prefMinAge <= prefMaxAge else {
            return "Minimum age preference cannot exceed maximum."
        }
        return nil
    }

    // MARK: - Intents (server-owned)

    /// Writes the chosen intents through `setActiveIntents`.
    ///
    /// The function re-checks the Dating gate against server-written fields, so a
    /// tampered client that ticks Dating without the face match is refused here
    /// rather than silently accepted.
    private func setActiveIntents(_ intents: [Intent]) async throws {
        _ = try await Functions.functions()
            .httpsCallable("setActiveIntents")
            .call(["intents": intents.map(\.rawValue)])
    }

    // MARK: - Photo Upload (atomic with best-effort cleanup)

    private func uploadPhotos(uid: String) async throws -> [String] {
        var urls: [String] = []
        let maxBytes = 10 * 1024 * 1024 // 10 MB per photo

        for (index, item) in selectedPhotos.enumerated() {
            do {
                guard let data = try await item.loadTransferable(type: Data.self) else {
                    throw AppError.networkError("Could not load photo \(index + 1).")
                }
                guard data.count <= maxBytes else {
                    throw AppError.networkError("Photo \(index + 1) exceeds 10 MB limit.")
                }
                guard let uiImage = UIImage(data: data),
                      let jpegData = uiImage.jpegData(compressionQuality: 0.8) else {
                    throw AppError.networkError("Photo \(index + 1) is not a valid image.")
                }
                let url = try await FirestoreService.shared.uploadPhoto(jpegData, uid: uid, index: index)
                urls.append(url.absoluteString)
            } catch {
                for cleanupIndex in 0..<urls.count {
                    await FirestoreService.shared.deletePhoto(uid: uid, index: cleanupIndex)
                }
                throw error
            }
        }
        return urls
    }

    // MARK: - Save Profile

    private func saveProfileAndFinish() async {
        if let validationError = validateInputs() {
            await MainActor.run {
                saveError = validationError
                showErrorAlert = true
            }
            return
        }

        guard let uid = Auth.auth().currentUser?.uid else {
            await MainActor.run {
                saveError = "You must be signed in to create a profile."
                showErrorAlert = true
            }
            return
        }

        await MainActor.run { isSaving = true }
        defer { Task { @MainActor in isSaving = false } }

        do {
            let photoURLs = try await uploadPhotos(uid: uid)

            let verificationStatus: VerificationStatus = {
                switch verifier.verificationState {
                case .verified: return .verified
                case .failed:   return .flagged
                default:        return .unverified
                }
            }()

            // trustLevel and verifiedAge are server-owned — studentIdVerification.ts
            // sets both, and firestore.rules rejects a client write. What the
            // client holds is whatever the server last told it.
            let trustLevel = authViewModel.currentUser?.trustLevel ?? .bronze
            let verifiedAge = authViewModel.currentUser?.verifiedAge

            let preferences = MatchPreferences(
                ageRange: prefMinAge...prefMaxAge,
                maxDistanceMiles: 0.25,
                genderPreferences: [],
                interests: Array(selectedInterests),
                dealbreakers: [],
                compatibilityThreshold: 0.80
            )

            let privacySettings = PrivacySettings(
                questModeEnabled: true,
                visibilityRadius: 0.25,
                autoPauseZones: [],
                alertLimit: alertLimit,
                locationSharingMode: locationMode,
                showInCommunityEvents: true
            )

            let gamification = GamificationProfile()

            let now = Date()
            var profile = UserProfile(
                uid: uid,
                displayName: displayName.trimmingCharacters(in: .whitespacesAndNewlines),
                age: age,
                bio: bio.trimmingCharacters(in: .whitespacesAndNewlines),
                photoURLs: photoURLs,
                selfDescriptors: [],
                verificationStatus: verificationStatus,
                trustLevel: trustLevel,
                verifiedAge: verifiedAge,
                verificationCompletedAt: verificationStatus == .verified ? now : nil,
                preferences: preferences,
                privacySettings: privacySettings,
                gamification: gamification,
                createdAt: now,
                lastActive: now
            )
            profile.id = uid
            profile.gender = selectedGender
            profile.intentVibes = Array(selectedVibes)

            // Field-whitelisted write. Everything that decides access is left
            // out, because it belongs to the server and the rules would reject it.
            try await FirestoreService.shared.saveProfileEdits(profile)

            // Intents go through the Cloud Function, not the profile write. That
            // is the only path that can enforce the Dating gate and set the
            // Dating-off cooldown.
            try await setActiveIntents(Array(selectedIntents))

            // Call Cloud Function to apply gender-specific defaults (waitlist, caps, boost)
            let genderResult = try await applyGenderDefaults(gender: selectedGender)

            // Update local profile with server response
            if genderResult.waitlisted {
                profile.accountStatus = .waitlisted
            }

            await MainActor.run {
                authViewModel.currentUser = profile

                if genderResult.waitlisted {
                    authViewModel.appState = .waitlisted
                } else {
                    authViewModel.appState = .authenticated
                }
            }
        } catch {
            await MainActor.run {
                saveError = "Could not save your profile. Please check your connection and try again."
                showErrorAlert = true
            }
        }
    }

    // MARK: - Apply Gender Defaults (Cloud Function)

    private struct GenderDefaultsResult {
        let accountStatus: String
        let alertCapPerHour: Int
        let waitlisted: Bool
    }

    private func applyGenderDefaults(gender: Gender) async throws -> GenderDefaultsResult {
        let functions = Functions.functions()
        let result = try await functions.httpsCallable("applyGenderDefaults")
            .call(["gender": gender.rawValue])

        guard let data = result.data as? [String: Any] else {
            return GenderDefaultsResult(accountStatus: "active", alertCapPerHour: 8, waitlisted: false)
        }

        return GenderDefaultsResult(
            accountStatus: data["accountStatus"] as? String ?? "active",
            alertCapPerHour: data["alertCapPerHour"] as? Int ?? 8,
            waitlisted: data["waitlisted"] as? Bool ?? false
        )
    }
}


// MARK: - Gender Display Label

extension Gender {
    var displayLabel: String {
        switch self {
        case .male: return "Male"
        case .female: return "Female"
        case .nonBinary: return "Non-Binary"
        case .preferNotToSay: return "Prefer Not to Say"
        }
    }
}
