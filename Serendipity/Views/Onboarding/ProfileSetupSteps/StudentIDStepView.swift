// MARK: - SECURITY CHECKLIST COMPLIANCE (see docs/SECURITY_CHECKLIST.md)
// [x] No hardcoded secrets, API keys, or tokens
// [x] The student ID image never lands in app state beyond the frame needed to
//     submit it — it is not written to the profile, not cached, not shown back
// [x] Upload goes to the write-only verification prefix; storage.rules makes the
//     object unreadable to every client, including the person who uploaded it
// [x] The pass/fail decision is the server's. The on-device face hint here is
//     shown to the user so they can retake a bad photo, and gates nothing.
// [x] Failure copy is one generic message — it never says which check failed,
//     because that would tell someone holding a borrowed card what to fix
// [x] No PII rendered or logged — no extracted name, DOB, or card number
// [x] Design system: v2 (DQFormParts, @Environment(\.dq)) — no v1 tokens

import SwiftUI
import PhotosUI

// MARK: - StudentIDStepView

/// Gate 2: student ID card photo + liveness. This is what opens Quest Mode, and
/// it is deliberately stricter than Fizz — an .edu address gets you into the
/// community, not into proximity scanning.
///
/// When the card and the liveness selfie also match, the same submission opens
/// the Dating intent and NameDrop.
struct StudentIDStepView: View {
    @ObservedObject var verifier: SafetyVerifier
    var profileAge: Int
    var onVerified: () -> Void

    @Environment(\.dq) private var p

    @State private var showLiveness = false
    @State private var cardItem: PhotosPickerItem?
    @State private var isSubmitting = false

    var body: some View {
        VStack(alignment: .leading, spacing: DQSpace.gutter) {
            header

            switch verifier.verificationState {
            case .idle, .failed:
                livenessPrompt
            case .livenessCheck:
                livenessPrompt
            case .capturingID:
                cardPrompt
            case .uploading, .processing:
                DQEmptyState(symbol: "hourglass",
                             title: "Checking your ID",
                             message: "This takes a few seconds.")
            case .verified:
                verifiedSummary
            }

            if case .failed(let message) = verifier.verificationState {
                Text(message)
                    .font(DQFont.bodyS)
                    .foregroundStyle(p.danger)
                    .accessibilityLabel("Error: \(message)")
            }
        }
        .fullScreenCover(isPresented: $showLiveness) {
            LivenessCheckView(livenessDetector: verifier.livenessDetector) { selfie in
                showLiveness = false
                if let selfie { verifier.completeLivenessCheck(selfie: selfie) }
            }
        }
        .onChange(of: cardItem) { _, item in
            guard let item else { return }
            Task { await submit(item) }
        }
        .modifier(DQBlockingSave(isActive: isSubmitting, title: "Checking your ID"))
    }

    // MARK: - Sections

    private var header: some View {
        VStack(alignment: .leading, spacing: DQSpace.tight) {
            Text("Verify you're a student")
                .font(DQFont.displayS)
                .foregroundStyle(p.text)

            Text("A photo of your student ID and a quick selfie. This is what lets "
                 + "you see who's nearby on campus.")
                .font(DQFont.body)
                .foregroundStyle(p.text2)
        }
    }

    private var livenessPrompt: some View {
        VStack(alignment: .leading, spacing: DQSpace.block) {
            DQAuthButton(title: "Start liveness check", kind: .filled) {
                verifier.beginVerification()
                showLiveness = true
            }
            DQFootnote(text: "We'll ask you to turn your head and blink. "
                       + "The frames are used once and deleted.")
        }
    }

    private var cardPrompt: some View {
        VStack(alignment: .leading, spacing: DQSpace.block) {
            PhotosPicker(selection: $cardItem, matching: .images) {
                Text("Photograph your student ID")
                    .font(DQFont.uiSized(14, .bold))
                    .foregroundStyle(p.ctaText)
                    .frame(maxWidth: .infinity)
                    .frame(height: DQSize.ctaHeight)
                    .background(Capsule().fill(p.cta))
                    .contentShape(Capsule())
            }

            DQFootnote(text: "Your ID is never shown on your profile and never "
                       + "appears to anyone nearby. It's deleted once it's checked.")
        }
    }

    private var verifiedSummary: some View {
        VStack(alignment: .leading, spacing: DQSpace.block) {
            DQEmptyState(symbol: "checkmark.seal",
                         title: "You're verified",
                         message: verifier.studentIDStatus.isFaceMatched
                            ? "Quest Mode is open, and you can turn on Dating if you want it."
                            : "Quest Mode is open. Dating needs your ID and selfie to match — "
                              + "you can retry that any time.")

            DQAuthButton(title: "Continue", kind: .filled) { onVerified() }
        }
    }

    // MARK: - Submit

    private func submit(_ item: PhotosPickerItem) async {
        isSubmitting = true
        defer { isSubmitting = false }

        guard let data = try? await item.loadTransferable(type: Data.self),
              let image = UIImage(data: data) else { return }

        await verifier.processStudentIDCard(image, profileAge: profileAge)

        // Deliberately dropped as soon as it has been submitted. Holding the
        // card image in view state past this point buys nothing and risks it
        // surviving into a snapshot or a state restoration.
        cardItem = nil

        if case .verified = verifier.verificationState { onVerified() }
    }
}
