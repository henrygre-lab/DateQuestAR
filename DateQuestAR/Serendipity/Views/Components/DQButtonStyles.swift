import SwiftUI

// MARK: - Primary (filled accent)

struct DQPrimaryButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(DQ.Typography.buttonLabel())
            .foregroundStyle(DQ.Colors.textPrimary)
            .frame(maxWidth: .infinity)
            .frame(height: DQ.Sizing.buttonHeight)
            .background(isEnabled ? DQ.Colors.accent : DQ.Colors.accent.opacity(0.4))
            .clipShape(RoundedRectangle(cornerRadius: DQ.Radii.large))
            .scaleEffect(configuration.isPressed ? 0.97 : 1.0)
            .animation(reduceMotion ? nil : DQ.Anim.quick, value: configuration.isPressed)
            .onChange(of: configuration.isPressed) { _, pressed in
                if pressed { UIImpactFeedbackGenerator(style: .medium).impactOccurred() }
            }
    }
}

// MARK: - Secondary (ghost / bordered)

struct DQSecondaryButtonStyle: ButtonStyle {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(DQ.Typography.bodyBold())
            .foregroundStyle(DQ.Colors.textPrimary)
            .frame(maxWidth: .infinity)
            .frame(height: DQ.Sizing.oauthButtonHeight)
            .background(DQ.Colors.surfaceElevated)
            .clipShape(RoundedRectangle(cornerRadius: DQ.Radii.medium))
            .scaleEffect(configuration.isPressed ? 0.96 : 1.0)
            .animation(reduceMotion ? nil : DQ.Anim.quick, value: configuration.isPressed)
    }
}

// MARK: - Convenience extensions

extension ButtonStyle where Self == DQPrimaryButtonStyle {
    static var dqPrimary: DQPrimaryButtonStyle { DQPrimaryButtonStyle() }
}

extension ButtonStyle where Self == DQSecondaryButtonStyle {
    static var dqSecondary: DQSecondaryButtonStyle { DQSecondaryButtonStyle() }
}
