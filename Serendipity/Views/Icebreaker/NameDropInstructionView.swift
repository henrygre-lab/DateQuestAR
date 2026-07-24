import SwiftUI

// MARK: - NameDrop Instruction View

struct NameDropInstructionView: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ZStack {
            DQ.Colors.mono0.ignoresSafeArea()
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
