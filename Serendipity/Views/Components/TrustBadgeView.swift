import SwiftUI

struct TrustBadgeView: View {
    let trustLevel: UserProfile.TrustLevel
    let size: BadgeSize

    enum BadgeSize {
        case small   // 24pt, icon only — for photo overlays
        case medium  // icon + label — for cards/banners
    }

    var body: some View {
        switch size {
        case .small:
            smallBadge
        case .medium:
            mediumBadge
        }
    }

    // MARK: - Small (overlay)

    private var smallBadge: some View {
        ZStack {
            Circle()
                .fill(Color.black.opacity(0.6))
                .frame(width: 24, height: 24)
            Image(systemName: iconName)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(tierColor)
        }
        .accessibilityLabel("Trust level: \(trustLevel.rawValue)")
    }

    // MARK: - Medium (card/banner)

    private var mediumBadge: some View {
        HStack(spacing: DQ.Spacing.xxxs) {
            Image(systemName: iconName)
                .font(.system(size: 13, weight: .semibold))
            Text(trustLevel.rawValue.capitalized)
                .font(DQ.Typography.caption())
        }
        .foregroundStyle(tierColor)
        .padding(.horizontal, DQ.Spacing.sm)
        .padding(.vertical, DQ.Spacing.xxxs)
        .background(tierColor.opacity(0.15))
        .clipShape(Capsule())
        .accessibilityLabel("Trust level: \(trustLevel.rawValue)")
    }

    // MARK: - Helpers

    private var tierColor: Color {
        DQ.Colors.trustColor(for: trustLevel)
    }

    private var iconName: String {
        switch trustLevel {
        case .bronze:   "shield"
        case .silver:   "shield.lefthalf.filled"
        case .gold:     "shield.fill"
        case .platinum: "checkmark.shield.fill"
        }
    }
}
