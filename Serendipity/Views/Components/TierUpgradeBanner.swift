import SwiftUI

/// Calm confirmation that a post-meet rating moved the match up a trust tier
/// (e.g. Gold → Platinum). Deliberately understated — a quiet tier-tinted row,
/// no bounce or glow. Presentational; pass the achieved level.
struct TierUpgradeBanner: View {
    let level: UserProfile.TrustLevel

    private var tierColor: Color { DQ.Colors.trustColor(for: level) }

    var body: some View {
        HStack(spacing: DQ.Spacing.xs) {
            Image(systemName: "arrow.up.circle.fill")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(tierColor)
            Text("Trust upgraded to \(level.rawValue.capitalized)")
                .font(DQ.Typography.caption())
                .foregroundStyle(DQ.Colors.mono900)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, DQ.Spacing.md)
        .padding(.vertical, DQ.Spacing.sm)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: DQ.Radii.medium).fill(tierColor.opacity(0.12)))
        .overlay(RoundedRectangle(cornerRadius: DQ.Radii.medium).stroke(tierColor.opacity(0.3), lineWidth: 1))
        .accessibilityLabel("Trust upgraded to \(level.rawValue)")
    }
}
