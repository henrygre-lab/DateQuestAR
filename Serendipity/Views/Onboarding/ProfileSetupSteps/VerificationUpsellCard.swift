import SwiftUI

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
