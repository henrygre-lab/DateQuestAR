import SwiftUI

struct OAuthButton: View {
    var label: String
    var icon: String
    var isLoading: Bool = false
    var isDisabled: Bool = false
    var action: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isPressed = false

    var body: some View {
        Button {
            guard !isLoading, !isDisabled else { return }
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            action()
        } label: {
            HStack(spacing: DQ.Spacing.xs) {
                if isLoading {
                    ProgressView().tint(DQ.Colors.textPrimary)
                } else {
                    Image(systemName: icon)
                    Text(label)
                }
            }
            .font(DQ.Typography.bodyBold())
            .foregroundStyle(isDisabled ? DQ.Colors.textQuaternary : DQ.Colors.textPrimary)
            .frame(maxWidth: .infinity)
            .frame(height: DQ.Sizing.oauthButtonHeight)
            .background(DQ.Colors.surfaceElevated)
            .clipShape(RoundedRectangle(cornerRadius: DQ.Radii.medium))
        }
        .scaleEffect(isPressed ? 0.96 : 1.0)
        .animation(reduceMotion ? nil : DQ.Anim.quick, value: isPressed)
        .simultaneousGesture(
            DragGesture(minimumDistance: 0)
                .onChanged { _ in isPressed = true }
                .onEnded { _ in isPressed = false }
        )
        .disabled(isLoading || isDisabled)
        .accessibilityLabel("Sign in with \(label)")
        .accessibilityAddTraits(isLoading ? .updatesFrequently : [])
        .accessibilityHint(isLoading ? "Loading" : "Double tap to sign in with \(label)")
    }
}
