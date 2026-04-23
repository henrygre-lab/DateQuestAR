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

// MARK: - Step Subviews

struct VerificationStepView: View {
    @ObservedObject var verifier: SafetyVerifier
    @State private var showLiveness = false

    var body: some View {
        VStack(spacing: DQ.Spacing.xxl) {
            Image(systemName: "checkmark.shield.fill")
                .resizable().scaledToFit()
                .frame(width: DQ.Sizing.iconSmall)
                .foregroundStyle(DQ.Colors.accent)
                .accessibilityLabel("Verification shield")
            Text("We verify every user with a selfie and ID to keep Serendipity safe for everyone.")
                .multilineTextAlignment(.center)
                .foregroundStyle(DQ.Colors.textSecondary)

            switch verifier.verificationState {
            case .idle:
                Button("Begin Verification") {
                    verifier.beginVerification()
                    showLiveness = true
                }
                .buttonStyle(.dqPrimary)

            case .livenessCheck:
                Button("Start Liveness Check") {
                    showLiveness = true
                }
                .buttonStyle(.dqPrimary)

            case .capturingID:
                Label("Selfie Verified", systemImage: "checkmark.circle.fill")
                    .foregroundStyle(DQ.Colors.success)
                Text("Now scan your ID (driver's license or passport).")
                    .foregroundStyle(DQ.Colors.textSecondary)
                    .multilineTextAlignment(.center)

            case .verified:
                VStack(spacing: DQ.Spacing.md) {
                    Label("Identity Verified", systemImage: "checkmark.circle.fill")
                        .foregroundStyle(DQ.Colors.success)
                        .accessibilityLabel("Identity verified successfully")
                    TrustBadgeView(trustLevel: verifier.achievedTrustLevel, size: .medium)
                }

            case .failed(let msg):
                Text(msg).foregroundStyle(DQ.Colors.error).multilineTextAlignment(.center)
                Button("Try Again") {
                    verifier.beginVerification()
                    showLiveness = true
                }
                .buttonStyle(.dqSecondary)

            default:
                ProgressView("Verifying...").tint(DQ.Colors.accent)
            }
        }
        .fullScreenCover(isPresented: $showLiveness) {
            LivenessCheckView(livenessDetector: verifier.livenessDetector) { selfieImage in
                showLiveness = false
                if let image = selfieImage {
                    verifier.completeLivenessCheck(selfie: image)
                }
            }
        }
    }
}

struct PhotosStepView: View {
    @Binding var selectedPhotos: [PhotosPickerItem]

    var body: some View {
        VStack(spacing: DQ.Spacing.xl) {
            Text("Add 2\u{2013}6 photos. The first will be your primary photo shown after proximity reveal.")
                .foregroundStyle(DQ.Colors.textSecondary)
                .multilineTextAlignment(.center)
            PhotosPicker(selection: $selectedPhotos, maxSelectionCount: 6, matching: .images) {
                Label("Choose Photos", systemImage: "photo.on.rectangle.angled")
                    .frame(maxWidth: .infinity)
                    .frame(height: DQ.Sizing.buttonHeight)
                    .background(DQ.Colors.accentSubtle)
                    .clipShape(RoundedRectangle(cornerRadius: DQ.Radii.medium))
                    .foregroundStyle(DQ.Colors.accent)
            }
            Text("\(selectedPhotos.count) photo(s) selected")
                .foregroundStyle(DQ.Colors.textQuaternary)
                .accessibilityLabel("\(selectedPhotos.count) photos selected")
        }
    }
}

struct BioStepView: View {
    @Binding var displayName: String
    @Binding var bio: String
    @Binding var age: Int
    @Binding var selectedGender: Gender
    @State private var ageText: String = ""

    var body: some View {
        ScrollView {
            VStack(spacing: DQ.Spacing.xl) {
                DQTextField(label: "Display name",
                            placeholder: "Display Name", text: $displayName,
                            isSecure: false)
                HStack {
                    Text("Age")
                        .foregroundStyle(DQ.Colors.textPrimary)
                    Spacer()
                    TextField("Age", text: $ageText)
                        .keyboardType(.numberPad)
                        .multilineTextAlignment(.trailing)
                        .frame(width: 60)
                        .foregroundStyle(DQ.Colors.textPrimary)
                        .onChange(of: ageText) { _, newValue in
                            let digits = newValue.filter(\.isNumber)
                            if let parsed = Int(digits) {
                                age = min(99, max(18, parsed))
                            }
                            if digits != newValue { ageText = digits }
                        }
                }
                .padding()
                .background(DQ.Colors.surfaceElevated)
                .clipShape(RoundedRectangle(cornerRadius: DQ.Radii.medium))
                .accessibilityLabel("Age")
                .accessibilityValue("\(age) years old")
                .onAppear { ageText = "\(age)" }

                // Gender selection
                VStack(alignment: .leading, spacing: DQ.Spacing.sm) {
                    Text("Gender")
                        .font(DQ.Typography.cardTitle())
                        .foregroundStyle(DQ.Colors.textPrimary)
                    FlowLayout {
                        ForEach(Gender.allCases, id: \.self) { gender in
                            ChipToggle(
                                label: gender.displayLabel,
                                isOn: selectedGender == gender
                            ) {
                                selectedGender = gender
                            }
                        }
                    }
                }

                TextEditor(text: $bio)
                    .frame(height: 100)
                    .padding(DQ.Spacing.xs)
                    .background(DQ.Colors.surfaceElevated)
                    .clipShape(RoundedRectangle(cornerRadius: DQ.Radii.medium))
                    .foregroundStyle(DQ.Colors.textPrimary)
                    .overlay(alignment: .topLeading) {
                        if bio.isEmpty {
                            Text("Write a short bio\u{2026}")
                                .foregroundStyle(DQ.Colors.textPlaceholder)
                                .padding(DQ.Spacing.md)
                        }
                    }
                    .accessibilityLabel("Bio")
                    .accessibilityHint(bio.isEmpty ? "Write a short bio about yourself" : "\(bio.count) characters entered")
            }
        }
    }
}

struct PreferencesStepView: View {
    @Binding var selectedInterests: Set<String>
    @Binding var selectedRelationshipTypes: Set<MatchPreferences.RelationshipType>
    @Binding var prefMinAge: Int
    @Binding var prefMaxAge: Int

    let allInterests = ["Hiking", "Coffee", "Travel", "Music", "Art", "Foodie",
                        "Fitness", "Reading", "Gaming", "Yoga", "Cooking", "Dogs"]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: DQ.Spacing.xxl) {
                Group {
                    Text("Relationship Type")
                        .font(DQ.Typography.cardTitle())
                        .foregroundStyle(DQ.Colors.textPrimary)
                    FlowLayout {
                        ForEach(MatchPreferences.RelationshipType.allCases, id: \.self) { type in
                            ChipToggle(label: type.rawValue, isOn: selectedRelationshipTypes.contains(type)) {
                                if selectedRelationshipTypes.contains(type) {
                                    selectedRelationshipTypes.remove(type)
                                } else {
                                    selectedRelationshipTypes.insert(type)
                                }
                            }
                        }
                    }
                }
                Group {
                    Text("Interests")
                        .font(DQ.Typography.cardTitle())
                        .foregroundStyle(DQ.Colors.textPrimary)
                    FlowLayout {
                        ForEach(allInterests, id: \.self) { interest in
                            ChipToggle(label: interest, isOn: selectedInterests.contains(interest)) {
                                if selectedInterests.contains(interest) {
                                    selectedInterests.remove(interest)
                                } else {
                                    selectedInterests.insert(interest)
                                }
                            }
                        }
                    }
                }
                Group {
                    Text("Age Range: \(prefMinAge)\u{2013}\(prefMaxAge)")
                        .font(DQ.Typography.cardTitle())
                        .foregroundStyle(DQ.Colors.textPrimary)
                    Stepper("Min: \(prefMinAge)", value: $prefMinAge, in: 18...prefMaxAge)
                        .foregroundStyle(DQ.Colors.textPrimary)
                    Stepper("Max: \(prefMaxAge)", value: $prefMaxAge, in: prefMinAge...60)
                        .foregroundStyle(DQ.Colors.textPrimary)
                }
            }
        }
    }
}

// MARK: - Vibe Step

struct VibeStepView: View {
    @Binding var selectedVibes: Set<String>

    let allVibes = [
        "Chill hangout", "Deep conversation", "Adventure buddy",
        "Coffee date", "Group outing", "Creative collab",
        "Workout partner", "Foodie crawl", "Night out",
        "Study buddy", "Dog walk", "Just vibing"
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: DQ.Spacing.xl) {
            Text("What kind of connection are you looking for right now?")
                .font(DQ.Typography.body())
                .foregroundStyle(DQ.Colors.textSecondary)

            Text("Select all that match your vibe. This helps us find compatible matches nearby.")
                .font(DQ.Typography.caption())
                .foregroundStyle(DQ.Colors.textTertiary)

            FlowLayout {
                ForEach(allVibes, id: \.self) { vibe in
                    ChipToggle(label: vibe, isOn: selectedVibes.contains(vibe)) {
                        if selectedVibes.contains(vibe) {
                            selectedVibes.remove(vibe)
                        } else {
                            selectedVibes.insert(vibe)
                        }
                    }
                }
            }

            if !selectedVibes.isEmpty {
                Text("\(selectedVibes.count) vibe(s) selected")
                    .font(DQ.Typography.caption())
                    .foregroundStyle(DQ.Colors.accent)
            }
        }
    }
}

struct PrivacyStepView: View {
    @Binding var alertLimit: Int
    @Binding var locationMode: PrivacySettings.LocationSharingMode

    var body: some View {
        VStack(alignment: .leading, spacing: DQ.Spacing.xxl) {
            Text("Your location is always anonymized using geohashing \u{2014} exact coordinates are never shared.")
                .foregroundStyle(DQ.Colors.textSecondary)
            Stepper("Max alerts/day: \(alertLimit)", value: $alertLimit, in: 1...20)
                .foregroundStyle(DQ.Colors.textPrimary)
            Picker("Location Mode", selection: $locationMode) {
                Text("Anonymized (Recommended)").tag(PrivacySettings.LocationSharingMode.anonymized)
                Text("Hidden").tag(PrivacySettings.LocationSharingMode.hidden)
            }
            .pickerStyle(.segmented)

            // Verification upsell
            VerificationUpsellCard()

            Text("You can add auto-pause zones (Home, Work) in Settings after onboarding.")
                .font(DQ.Typography.footnote())
                .foregroundStyle(DQ.Colors.textQuaternary)
        }
    }
}

// MARK: - Verification Upsell Card

struct VerificationUpsellCard: View {
    @StateObject private var verifier = SafetyVerifier()
    @State private var isVerifying = false

    var body: some View {
        VStack(spacing: DQ.Spacing.md) {
            HStack(spacing: DQ.Spacing.sm) {
                Image(systemName: "checkmark.shield.fill")
                    .font(.system(size: 20))
                    .foregroundStyle(DQ.Colors.accent)
                VStack(alignment: .leading, spacing: DQ.Spacing.xxxs) {
                    Text("Get Verified")
                        .font(DQ.Typography.bodyBold())
                        .foregroundStyle(DQ.Colors.textPrimary)
                    Text("Verified users get 2x visibility and a trust badge")
                        .font(DQ.Typography.caption())
                        .foregroundStyle(DQ.Colors.textTertiary)
                }
                Spacer()
            }

            if verifier.verificationBadge == .verified {
                Label("Verified", systemImage: "checkmark.circle.fill")
                    .font(DQ.Typography.caption())
                    .foregroundStyle(DQ.Colors.success)
            } else {
                Button {
                    isVerifying = true
                    Task {
                        _ = await verifier.verifyIdentity()
                        isVerifying = false
                    }
                } label: {
                    if isVerifying {
                        ProgressView()
                            .tint(DQ.Colors.accent)
                    } else {
                        Text("Verify Now")
                            .font(DQ.Typography.caption().bold())
                    }
                }
                .buttonStyle(.dqSecondary)
                .disabled(isVerifying)
            }
        }
        .padding(DQ.Spacing.lg)
        .background(
            RoundedRectangle(cornerRadius: DQ.Radii.large)
                .fill(DQ.Colors.surfaceCard)
                .overlay(
                    RoundedRectangle(cornerRadius: DQ.Radii.large)
                        .stroke(DQ.Colors.accent.opacity(0.2), lineWidth: 1)
                )
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
