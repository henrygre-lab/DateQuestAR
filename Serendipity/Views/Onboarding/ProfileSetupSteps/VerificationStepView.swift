import SwiftUI

struct VerificationStepView: View {
    @ObservedObject var verifier: SafetyVerifier
    @Environment(\.dq) private var p
    @State private var showLiveness = false

    var body: some View {
        VStack(spacing: DQSpace.gutter) {
            // Leading glyphs stay reserved for trust, live and verify states —
            // this is one of them.
            Image(systemName: "checkmark.shield")
                .font(.system(size: 34, weight: .light))
                .foregroundStyle(p.verify)
                .accessibilityLabel("Verification shield")

            Text("We verify every user with a selfie and ID to keep Serendipity safe for everyone.")
                .font(DQFont.body)
                .foregroundStyle(p.text2)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)

            switch verifier.verificationState {
            case .idle:
                Button("Begin Verification") {
                    verifier.beginVerification()
                    showLiveness = true
                }
                .buttonStyle(.dqNeutral)

            case .livenessCheck:
                Button("Start Liveness Check") { showLiveness = true }
                    .buttonStyle(.dqNeutral)

            case .capturingID:
                verifiedLine("Selfie verified")
                Text("Now scan your ID (driver's license or passport).")
                    .font(DQFont.bodyS)
                    .foregroundStyle(p.text2)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)

            case .verified:
                VStack(spacing: DQSpace.tight) {
                    verifiedLine("Identity verified")
                    TrustChip(tier: verifier.achievedTrustLevel)
                }

            case .failed(let msg):
                Text(msg)
                    .font(DQFont.bodyS)
                    .foregroundStyle(p.danger)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                Button("Try Again") {
                    verifier.beginVerification()
                    showLiveness = true
                }
                .buttonStyle(.dqGhost)

            default:
                HStack(spacing: DQSpace.tight) {
                    ProgressView().tint(p.text2)
                    Text("Verifying…")
                        .font(DQFont.bodyS)
                        .foregroundStyle(p.text2)
                }
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

    private func verifiedLine(_ text: String) -> some View {
        HStack(spacing: DQSpace.tight) {
            Image(systemName: "checkmark")
                .font(.system(size: 10, weight: .heavy))
                .foregroundStyle(.white)
                .frame(width: 20, height: 20)
                .background(Circle().fill(p.verify))
            Text(text)
                .font(DQFont.uiSized(13, .semibold))
                .foregroundStyle(p.text)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(text)
    }
}
