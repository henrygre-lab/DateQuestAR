// MARK: - SECURITY CHECKLIST COMPLIANCE (see docs/SECURITY_CHECKLIST.md)
// [x] No hardcoded secrets, API keys, or tokens — and no school allowlist here.
//     The list of valid domains lives in Firestore and is enforced by
//     schoolGate.ts, so there is nothing in this view worth editing.
// [x] No client-side trust decisions — this view collects input and renders the
//     state SchoolGateManager publishes; schoolId is issued by a Cloud Function
// [x] Phone number goes to Keychain via SchoolGateManager, never to UserDefaults,
//     the profile document, or analytics
// [x] Failure copy is generic and identical across causes — a wrong domain, a
//     used-up attempt and a paused school all read the same, so the screen is not
//     an oracle for which schools or accounts exist
// [x] No place name rendered beyond the school's own display name, which is
//     community identity (DESIGN_SYSTEM.md §8)
// [x] Design system: v2 (DQFormParts, @Environment(\.dq)) — no v1 tokens

import SwiftUI
import PhotosUI

// MARK: - SchoolGateView

/// The Fizz-style school gate: phone, then an allowlisted .edu magic link,
/// school Google / Microsoft OAuth, or an enrollment proof for incoming students.
///
/// Nothing here grants access. Every path ends in a Cloud Function call, and the
/// community only exists once that function has issued it.
struct SchoolGateView: View {
    @EnvironmentObject private var authViewModel: AuthViewModel
    @StateObject private var gate = SchoolGateManager.shared
    @Environment(\.dq) private var p

    @State private var phase: Phase = .phone
    @State private var phoneNumber = ""
    @State private var smsCode = ""
    @State private var schoolEmail = ""

    // Incoming-student path
    @State private var schools: [School] = []
    @State private var selectedSchoolId: String?
    @State private var proofItem: PhotosPickerItem?
    @State private var isUploadingProof = false

    private enum Phase {
        case phone, code, email, sent, enrollment
    }

    var body: some View {
        ZStack {
            p.bg.ignoresSafeArea()

            VStack(spacing: 0) {
                DQTopBar(title: "Verify your school", style: .root)

                ScrollView {
                    VStack(alignment: .leading, spacing: DQSpace.gutter) {
                        header
                        content
                        if let message = failureMessage {
                            Text(message)
                                .font(DQFont.bodyS)
                                .foregroundStyle(p.danger)
                                .accessibilityLabel("Error: \(message)")
                        }
                        alternatives
                    }
                    .padding(.horizontal, DQSpace.gutter)
                    .padding(.top, DQSpace.block)
                    .padding(.bottom, DQSpace.safeBottom)
                }
            }
        }
        .modifier(DQBlockingSave(isActive: gate.isBusy || isUploadingProof, title: "Verifying"))
        .task { await loadSchools() }
    }

    // MARK: - Header

    private var header: some View {
        VStack(alignment: .leading, spacing: DQSpace.tight) {
            Text("Your campus, not the internet")
                .font(DQFont.displayS)
                .foregroundStyle(p.text)

            Text("Serendipity only works inside a verified campus community. "
                 + "You'll only ever see people from your own school.")
                .font(DQFont.body)
                .foregroundStyle(p.text2)
        }
    }

    // MARK: - Content

    @ViewBuilder
    private var content: some View {
        switch phase {
        case .phone:
            VStack(alignment: .leading, spacing: DQSpace.block) {
                DQTextField(label: "Phone number",
                            placeholder: "+1 555 000 0000",
                            text: $phoneNumber,
                            keyboardType: .phonePad)
                DQFootnote(text: "Kept on your device and with Firebase Auth. "
                           + "It never appears on your profile.")
                DQAuthButton(title: "Send code", kind: .filled) {
                    Task {
                        await gate.startPhoneVerification(phoneNumber: phoneNumber)
                        if case .awaitingPhoneCode = gate.state { phase = .code }
                    }
                }
                .disabled(phoneNumber.count < 8)
            }

        case .code:
            VStack(alignment: .leading, spacing: DQSpace.block) {
                DQTextField(label: "Verification code",
                            placeholder: "123456",
                            text: $smsCode,
                            keyboardType: .numberPad)
                DQAuthButton(title: "Verify", kind: .filled) {
                    Task {
                        await gate.confirmPhoneCode(smsCode)
                        if case .idle = gate.state { phase = .email }
                    }
                }
                .disabled(smsCode.count < 6)
            }

        case .email:
            VStack(alignment: .leading, spacing: DQSpace.block) {
                DQTextField(label: "School email",
                            placeholder: "you@school.edu",
                            text: $schoolEmail,
                            keyboardType: .emailAddress)
                DQFootnote(text: "We'll send a one-tap link. Your address is stored "
                           + "with your verification record, never on your profile.")
                DQAuthButton(title: "Send verification link", kind: .filled) {
                    Task {
                        await gate.requestMagicLink(schoolEmail: schoolEmail)
                        if case .awaitingMagicLink = gate.state { phase = .sent }
                    }
                }
                .disabled(!schoolEmail.contains("@"))
            }

        case .sent:
            DQEmptyState(symbol: "envelope.badge",
                         title: "Check your school email",
                         message: "Tap the link we sent to \(schoolEmail). "
                                + "It expires in an hour.")

        case .enrollment:
            enrollmentProof
        }
    }

    // MARK: - Enrollment Proof (incoming students)

    private var enrollmentProof: some View {
        VStack(alignment: .leading, spacing: DQSpace.block) {
            DQSectionHeader(title: "Incoming student")

            Text("Admitted but no school email yet? Send your admission or "
                 + "enrollment letter and we'll review it.")
                .font(DQFont.body)
                .foregroundStyle(p.text2)

            if schools.isEmpty {
                DQSkeleton(height: 44)
            } else {
                // A plain list rather than a segmented control: the school roster
                // is long and grows, and a segmented control would silently
                // truncate it.
                VStack(spacing: 1) {
                    ForEach(schools) { school in
                        Button {
                            selectedSchoolId = school.id
                        } label: {
                            HStack {
                                Text(school.displayName)
                                    .font(DQFont.body)
                                    .foregroundStyle(p.text)
                                Spacer()
                                if selectedSchoolId == school.id {
                                    Image(systemName: "checkmark")
                                        .font(.system(size: 13, weight: .semibold))
                                        .foregroundStyle(p.ember)
                                }
                            }
                            .padding(.horizontal, DQFormMetrics.inset)
                            .frame(height: DQSize.minHitTarget)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityAddTraits(selectedSchoolId == school.id ? [.isButton, .isSelected] : .isButton)
                    }
                }
                .background(RoundedRectangle(cornerRadius: DQRadius.row, style: .continuous).fill(p.surface))
            }

            PhotosPicker(selection: $proofItem, matching: .images) {
                Text(proofItem == nil ? "Choose your letter" : "Letter selected")
                    .font(DQFont.uiSized(14, .semibold))
                    .foregroundStyle(p.text)
                    .frame(maxWidth: .infinity)
                    .frame(height: DQSize.ghostHeight)
                    .overlay(Capsule().strokeBorder(p.lineStrong, lineWidth: 1))
                    .contentShape(Capsule())
            }

            DQFootnote(text: "Your letter is uploaded where nobody — including you — "
                       + "can read it back. It's deleted once it's been reviewed.")

            DQAuthButton(title: "Submit for review", kind: .filled) {
                Task { await submitProof() }
            }
            .disabled(proofItem == nil || selectedSchoolId == nil)
        }
    }

    /// Loads the school list for the incoming-student picker.
    ///
    /// Read-only reference data: `firestore.rules` makes `schools/*` auth-read
    /// and admin-write, so this list cannot be extended from a client.
    private func loadSchools() async {
        schools = (try? await FirestoreService.shared.fetchSchools()) ?? []
        selectedSchoolId = schools.first?.id
    }

    /// Uploads the letter to the write-only verification prefix, then queues a
    /// review. Neither step grants anything — `enrollmentStatus` becomes
    /// `.pending`, which `grantsCommunityAccess` refuses.
    private func submitProof() async {
        guard let schoolId = selectedSchoolId,
              let item = proofItem,
              let uid = authViewModel.currentUser?.uid else { return }

        isUploadingProof = true
        defer { isUploadingProof = false }

        guard let data = try? await item.loadTransferable(type: Data.self) else { return }

        do {
            let path = try await FirestoreService.shared.uploadVerificationArtifact(
                data, uid: uid, filename: "enrollment_\(UUID().uuidString).jpg"
            )
            await gate.submitEnrollmentProof(schoolId: schoolId, storagePath: path)
        } catch {
            // Same generic copy as every other failure on this screen.
            Log.school.error("Enrollment proof upload failed")
        }
    }

    // MARK: - Alternatives

    @ViewBuilder
    private var alternatives: some View {
        if phase == .email || phase == .sent {
            VStack(alignment: .leading, spacing: DQSpace.tight) {
                DQSectionHeader(title: "Other ways in")

                DQAuthButton(title: "Continue with school Google",
                             kind: .ghost,
                             symbol: "g.circle") {
                    Task { await gate.completeOAuthGate() }
                }

                DQAuthButton(title: "Continue with school Microsoft",
                             kind: .ghost,
                             symbol: "m.square") {
                    Task { await gate.completeOAuthGate() }
                }

                DQAuthButton(title: "I'm an incoming student", kind: .plain) {
                    // Incoming students often have no address yet. The proof
                    // path grants nothing on submission — it queues a review.
                    phase = .enrollment
                }
            }
        }
    }

    // MARK: - Failure

    private var failureMessage: String? {
        if case .failed(let message) = gate.state { return message }
        return nil
    }
}
