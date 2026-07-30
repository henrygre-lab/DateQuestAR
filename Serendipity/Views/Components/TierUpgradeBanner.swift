import SwiftUI

/// Confirmation that a post-meet rating moved the partner up a trust tier —
/// e.g. Gold → Platinum (§5 TierUpgradeBanner). Shows the transition, the
/// reason it happened, and a tier-filled circle, under a slow breathing glow.
/// No medals, stars, XP bars or confetti — trust is never gamified.
///
/// Presentational; pass the tier before and after.
struct TierUpgradeBanner: View {
    let from: UserProfile.TrustLevel
    let to: UserProfile.TrustLevel

    @Environment(\.dq) private var p
    @Environment(\.dqTheme) private var theme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var glowing = false

    private var toColor: Color { to.dq.color(p) }

    var body: some View {
        HStack(spacing: 13) {
            VStack(alignment: .leading, spacing: 5) {
                Text("Your trust tier")
                    .font(DQFont.labelSized(9, .semibold))
                    .tracking(DQFont.track(9, em: 0.18))
                    .textCase(.uppercase)
                    .foregroundStyle(p.text3)

                HStack(spacing: DQSpace.tight) {
                    tierLabel(from, font: DQFont.uiSized(13, .bold), color: p.text2, glyph: 10)

                    Image(systemName: "arrow.right")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(p.text3)

                    tierLabel(to, font: DQFont.titleS, color: toColor, glyph: 12)
                }

                Text("\(to.dq.requirement) · upgraded just now")
                    .font(DQFont.uiSized(10.5, .medium))
                    .foregroundStyle(p.text2)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 0)

            Image(systemName: "diamond.fill")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(toColor)
                .frame(width: 42, height: 42)
                .background(Circle().fill(to.dq.fill(p, theme)))
        }
        .padding(.horizontal, 17)
        .padding(.vertical, 15)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: DQRadius.card, style: .continuous)
                .fill(p.surface)
        )
        .overlay(
            RoundedRectangle(cornerRadius: DQRadius.card, style: .continuous)
                .strokeBorder(p.line, lineWidth: 1)
        )
        .shadow(color: toColor.opacity(0.4), radius: glowing ? DQMotion.tierGlowRadius : 0)
        .onAppear {
            guard !reduceMotion else { return }
            withAnimation(DQMotion.tierGlow) { glowing = true }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(
            "Trust tier upgraded from \(from.dq.name) to \(to.dq.name). \(to.dq.requirement)."
        )
    }

    private func tierLabel(
        _ tier: UserProfile.TrustLevel,
        font: Font,
        color: Color,
        glyph: CGFloat
    ) -> some View {
        HStack(spacing: 5) {
            Image(systemName: "diamond.fill")
                .font(.system(size: glyph, weight: .semibold))
            Text(tier.dq.name)
                .font(font)
        }
        .foregroundStyle(color)
    }
}
