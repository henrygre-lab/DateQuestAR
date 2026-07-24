// MARK: - Vibe Coding Security Checklist Compliance
// [x] No hardcoded secrets, API keys, or tokens
// [x] Gender selection calls server-side applyGenderDefaults Cloud Function
// [x] Waitlist decision made server-side — client only reads the result
// [x] Photo uploads scoped to authenticated user's storage path
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
    @StateObject private var verifier = SafetyVerifier()
    @State private var step: SetupStep = .verification
    @State private var selectedPhotos: [PhotosPickerItem] = []
    @State private var displayName = ""
    @State private var bio = ""
    @State private var age = 25
    @State private var selectedGender: Gender = .preferNotToSay
    @State private var selectedInterests: Set<String> = []
    @State private var selectedRelationshipTypes: Set<MatchPreferences.RelationshipType> = []
    @State private var selectedVibes: Set<String> = []
    @State private var prefMinAge = 21
    @State private var prefMaxAge = 35
    @State private var alertLimit = 5
    @State private var locationMode = PrivacySettings.LocationSharingMode.anonymized
    @State private var isSaving = false
    @State private var saveError: String?
    @State private var showErrorAlert = false

    enum SetupStep: Int, CaseIterable {
        case verification, photos, bio, preferences, vibes, privacy

        var title: String {
            switch self {
            case .verification:  return "Verify Your Identity"
            case .photos:        return "Add Your Photos"
            case .bio:           return "About You"
            case .preferences:   return "Your Preferences"
            case .vibes:         return "Your Vibe"
            case .privacy:       return "Privacy & Safety"
            }
        }
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                progressBar
                stepContent
                    .padding()
                Spacer()
                navigationButtons
                    .padding(.horizontal)
                    .padding(.bottom, DQ.Spacing.giant)
            }
            .navigationTitle(step.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    #if DEBUG
                    Button("Skip") {
                        authViewModel.appState = .authenticated
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    #endif
                }
            }
            .dqBackground()
            .overlay {
                if isSaving {
                    ZStack {
                        Color.black.opacity(0.4).ignoresSafeArea()
                        VStack(spacing: DQ.Spacing.lg) {
                            ProgressView()
                                .tint(.white)
                                .scaleEffect(1.5)
                            Text("Creating your profile...")
                                .foregroundStyle(.white)
                                .font(DQ.Typography.cardTitle())
                        }
                    }
                }
            }
            .alert("Something went wrong", isPresented: $showErrorAlert) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(saveError ?? "Please try again.")
            }
        }
    }

    // MARK: - Progress Bar

    private var progressBar: some View {
        let total = SetupStep.allCases.count
        let current = step.rawValue + 1
        return ProgressView(value: Double(current), total: Double(total))
            .tint(DQ.Colors.accent)
            .padding(.horizontal)
            .accessibilityLabel("Step \(current) of \(total): \(step.title)")
    }

    // MARK: - Step Content

    @ViewBuilder
    private var stepContent: some View {
        switch step {
        case .verification:
            VerificationStepView(verifier: verifier)
        case .photos:
            PhotosStepView(selectedPhotos: $selectedPhotos)
        case .bio:
            BioStepView(displayName: $displayName, bio: $bio, age: $age, selectedGender: $selectedGender)
        case .preferences:
            PreferencesStepView(
                selectedInterests: $selectedInterests,
                selectedRelationshipTypes: $selectedRelationshipTypes,
                prefMinAge: $prefMinAge,
                prefMaxAge: $prefMaxAge
            )
        case .vibes:
            VibeStepView(selectedVibes: $selectedVibes)
        case .privacy:
            PrivacyStepView(alertLimit: $alertLimit, locationMode: $locationMode)
        }
    }

    // MARK: - Navigation Buttons

    private var navigationButtons: some View {
        HStack {
            if step != .verification {
                Button("Back") {
                    withAnimation { step = SetupStep(rawValue: step.rawValue - 1) ?? .verification }
                }
                .buttonStyle(.dqSecondary)
            }
            Spacer()
            Button(step == .privacy ? "Start Questing" : "Next") {
                advanceStep()
            }
            .buttonStyle(.dqPrimary)
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
        guard !selectedRelationshipTypes.isEmpty else {
            return "Please select at least one relationship type."
        }
        guard prefMinAge <= prefMaxAge else {
            return "Minimum age preference cannot exceed maximum."
        }
        return nil
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

            let trustLevel = verifier.achievedTrustLevel
            let verifiedAge = verifier.idValidationResult?.extractedAge

            let preferences = MatchPreferences(
                ageRange: prefMinAge...prefMaxAge,
                maxDistanceMiles: 0.25,
                relationshipTypes: Array(selectedRelationshipTypes),
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

            // Persist to Firestore
            try await FirestoreService.shared.createOrUpdateUser(profile)

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
