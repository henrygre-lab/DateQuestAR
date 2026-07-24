import SwiftUI

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
