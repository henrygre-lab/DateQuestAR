import SwiftUI

struct ChipToggle: View {
    var label: String
    var isOn: Bool
    var action: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Button {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            action()
        } label: {
            Text(label)
                .font(DQ.Typography.body())
                .padding(.horizontal, DQ.Spacing.lg)
                .padding(.vertical, DQ.Spacing.xs)
                .background(isOn ? DQ.Colors.accent : DQ.Colors.surfaceElevated)
                .foregroundStyle(DQ.Colors.textPrimary)
                .clipShape(Capsule())
        }
        .scaleEffect(isOn ? 1.0 : 0.97)
        .animation(reduceMotion ? nil : DQ.Anim.quick, value: isOn)
        .accessibilityLabel(label)
        .accessibilityAddTraits(isOn ? .isSelected : [])
        .accessibilityHint("Double tap to \(isOn ? "deselect" : "select")")
    }
}
