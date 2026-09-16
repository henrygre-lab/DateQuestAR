// MARK: - SECURITY CHECKLIST COMPLIANCE (see docs/SECURITY_CHECKLIST.md)
// [x] No hardcoded secrets, API keys, or tokens
// [x] NameDrop requires the student ID <-> liveness face match. This view refuses
//     to show the exchange instructions without it, RevealManager.completeReveal
//     refuses to advance the stage, and firestore.rules rejects a 'connected'
//     write without the faceMatched claim — three layers, the last authoritative.
// [x] canNameDrop reads server-written fields only; a client cannot grant itself
//     the exchange by editing local state
// [x] No contact details pass through this view — the exchange is iOS NameDrop,
//     device to device, and nothing here is stored or logged
// [x] No PII logged

import SwiftUI

// MARK: - NameDrop Instruction View

struct NameDropInstructionView: View {
    /// Whether this account has cleared the ID <-> liveness face match.
    ///
    /// Defaults to false: a caller that forgets to pass it gets the locked
    /// screen, which is the safe way round.
    var canNameDrop: Bool = false

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ZStack {
            DQ.Colors.mono0.ignoresSafeArea()
            if canNameDrop { instructions } else { locked }
        }
    }

    // MARK: - Locked

    /// Exchanging real identity is the moment the stakes rise, so it carries the
    /// same proof as the Dating intent even when the encounter is a Study one.
    private var locked: some View {
        VStack(spacing: DQ.Spacing.xxl) {
            Spacer()

            Image(systemName: "lock.shield")
                .font(.system(size: 60))
                .foregroundStyle(DQ.Colors.mono600)
                .accessibilityHidden(true)

            Text("Verify your student ID first")
                .font(DQ.Typography.screenTitle())
                .foregroundStyle(DQ.Colors.mono900)
                .multilineTextAlignment(.center)

            Text("Swapping contact details needs your student ID photo to match "
                 + "your selfie. It's a one-time check, and it's what keeps this "
                 + "from being a way to reach someone who never verified.")
                .font(DQ.Typography.body())
                .foregroundStyle(DQ.Colors.mono700)
                .multilineTextAlignment(.center)
                .padding(.horizontal, DQ.Spacing.lg)

            Spacer()

            Button("Close") { dismiss() }
                .buttonStyle(.dqSecondary)
                .padding(.horizontal, DQ.Spacing.xl)
        }
        .padding(DQ.Spacing.xl)
    }

    // MARK: - Instructions

    private var instructions: some View {
            VStack(spacing: DQ.Spacing.xxl) {
                Spacer()

                Image(systemName: "wave.3.right")
                    .font(.system(size: 60))
                    .foregroundStyle(DQ.Colors.signal)
                    .accessibilityHidden(true)

                Text("Exchange contact info")
                    .font(DQ.Typography.screenTitle())
                    .foregroundStyle(DQ.Colors.mono900)

                VStack(spacing: DQ.Spacing.lg) {
                    instructionStep(number: 1, text: "Hold the top of your iPhone close to the top of your match's iPhone.")
                    instructionStep(number: 2, text: "A NameDrop prompt will appear on both screens.")
                    instructionStep(number: 3, text: "Choose which contact info to share, then tap Share.")
                }
                .padding(.horizontal, DQ.Spacing.lg)

                Text("Both devices must be unlocked with iOS 17 or later.")
                    .font(DQ.Typography.caption())
                    .foregroundStyle(DQ.Colors.mono600)
                    .multilineTextAlignment(.center)

                Spacer()

                Button("Got it") {
                    dismiss()
                }
                .buttonStyle(.dqSignal)
                .padding(.horizontal, DQ.Spacing.xl)
            }
            .padding(DQ.Spacing.xl)
    }

    private func instructionStep(number: Int, text: String) -> some View {
        HStack(alignment: .top, spacing: DQ.Spacing.md) {
            Text("\(number)")
                .font(DQ.Typography.bodyBold())
                .foregroundStyle(DQ.Colors.signal)
                .frame(width: 28, height: 28)
                .background(DQ.Colors.signalSubtle)
                .clipShape(Circle())

            Text(text)
                .font(DQ.Typography.body())
                .foregroundStyle(DQ.Colors.mono700)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}
