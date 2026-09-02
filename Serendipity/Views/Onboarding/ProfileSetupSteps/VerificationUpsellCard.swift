// MARK: - SECURITY CHECKLIST COMPLIANCE (see docs/SECURITY_CHECKLIST.md)
// [x] No hardcoded secrets, API keys, or tokens
// [x] This is the OPTIONAL extra document check, not the campus gate. Quest Mode,
//     the Dating intent and NameDrop all read studentIDStatus, which only
//     submitStudentIDVerification can set — nothing here opens any of them.
// [x] verifyIdentity proxies through a Cloud Function; the provider API key never
//     reaches the client
// [x] The badge shown is the server's answer; no client-side promotion
// [x] No PII rendered or logged

import SwiftUI

// MARK: - Verification Upsell Card

/// The optional third-party document check, offered after the campus gates are
/// already satisfied. Deliberately does not promise access — the student ID check
/// is what opens things, and this sits on top of it.
struct VerificationUpsellCard: View {
    @StateObject private var verifier = SafetyVerifier()
    @Environment(\.dq) private var p
    @State private var isVerifying = false

    var body: some View {
        VStack(spacing: DQSpace.tight) {
            HStack(spacing: DQSpace.tight) {
                // A verify glyph, which §8 still allows a leading position.
                Image(systemName: "checkmark.shield")
                    .font(.system(size: 18, weight: .medium))
                    .foregroundStyle(p.verify)

                VStack(alignment: .leading, spacing: 3) {
                    Text("Add an extra verification")
                        .font(DQFont.uiSized(14, .semibold))
                        .foregroundStyle(p.text)
                    Text("Optional. Your student ID already covers Quest Mode — "
                         + "this adds a second trust signal on your profile.")
                        .font(DQFont.uiSized(11.5, .medium))
                        .foregroundStyle(p.text2)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
            }

            if verifier.verificationBadge == .verified {
                HStack(spacing: DQSpace.tight) {
                    Image(systemName: "checkmark")
                        .font(.system(size: 10, weight: .heavy))
                        .foregroundStyle(.white)
                        .frame(width: 20, height: 20)
                        .background(Circle().fill(p.verify))
                    Text("Verified")
                        .font(DQFont.uiSized(13, .semibold))
                        .foregroundStyle(p.text)
                    Spacer(minLength: 0)
                }
            } else {
                Button {
                    isVerifying = true
                    Task {
                        _ = await verifier.verifyIdentity()
                        isVerifying = false
                    }
                } label: {
                    if isVerifying {
                        ProgressView().tint(p.text2)
                    } else {
                        Text("Verify now")
                    }
                }
                .buttonStyle(.dqGhost)
                .disabled(isVerifying)
            }
        }
        .padding(DQSpace.card)
        .background(
            RoundedRectangle(cornerRadius: DQRadius.card, style: .continuous).fill(p.surface)
        )
        .overlay(
            RoundedRectangle(cornerRadius: DQRadius.card, style: .continuous)
                .strokeBorder(p.line, lineWidth: 1)
        )
    }
}
