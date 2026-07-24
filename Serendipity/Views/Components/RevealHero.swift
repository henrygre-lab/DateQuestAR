import SwiftUI

/// The progressive-reveal photo — the hero interaction of an encounter.
/// The whole photo unblurs uniformly as `progress` climbs (no partial face/eye
/// reveal). Identity (name/age) is gated behind `.connected`, mirroring the
/// production reveal contract. Presentational only; pass plain values.
struct RevealHero: View {
    let name: String
    let progress: Double
    let stage: RevealStage
    let trust: UserProfile.TrustLevel

    var height: CGFloat = 320

    // MARK: - Blur Curve
    // Continuous, driven by revealProgress, with the spec anchor points:
    // 0.0 → 40px, 0.3 → 20px, 0.7 → 12px, 1.0 → 0px. Piecewise-linear between.
    static func blurRadius(for progress: Double) -> CGFloat {
        let p = min(max(progress, 0), 1)
        func lerp(_ a: CGFloat, _ b: CGFloat, _ t: Double) -> CGFloat { a + (b - a) * CGFloat(t) }
        switch p {
        case ..<0.3: return lerp(40, 20, p / 0.3)
        case ..<0.7: return lerp(20, 12, (p - 0.3) / 0.4)
        default:     return lerp(12, 0, (p - 0.7) / 0.3)
        }
    }

    var body: some View {
        ZStack {
            photo
            overlays
        }
        .frame(maxWidth: .infinity)
        .frame(height: height)
        .clipShape(RoundedRectangle(cornerRadius: DQ.Radii.xxl))
        .overlay(
            RoundedRectangle(cornerRadius: DQ.Radii.xxl)
                .stroke(DQ.Colors.mono300, lineWidth: 1)
        )
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityLabel)
    }

    // MARK: - Photo (uniform blur across the whole image)

    private var photo: some View {
        // Neutral mono duotone stands in for the photo. The fill covers the full
        // frame so the blur stays uniform with no transparent edge halo.
        LinearGradient(
            colors: [DQ.Colors.mono400, DQ.Colors.mono200, DQ.Colors.mono100],
            startPoint: .top, endPoint: .bottom
        )
        .overlay(
            Text(initials)
                .font(DQ.Typography.mono(76, weight: .bold))
                .foregroundStyle(DQ.Colors.mono700)
        )
        .blur(radius: RevealHero.blurRadius(for: progress))
    }

    // MARK: - Overlays (lock chip + identity)

    private var overlays: some View {
        VStack {
            HStack {
                Spacer()
                if stage < .connected {
                    Label(lockLabel, systemImage: "lock.fill")
                        .font(DQ.Typography.mono(10, weight: .medium))
                        .foregroundStyle(DQ.Colors.mono900)
                        .padding(.horizontal, DQ.Spacing.sm)
                        .padding(.vertical, DQ.Spacing.xxxs)
                        .background(Capsule().fill(DQ.Colors.mono0.opacity(0.55)))
                }
            }
            Spacer()
            HStack(alignment: .bottom) {
                if stage >= .connected {
                    VStack(alignment: .leading, spacing: DQ.Spacing.xxs) {
                        Text(name)
                            .font(DQ.Typography.sectionHeader())
                            .foregroundStyle(DQ.Colors.mono900)
                        TrustBadgeView(trustLevel: trust, size: .medium)
                    }
                    .transition(.opacity)
                }
                Spacer()
                TrustBadgeView(trustLevel: trust, size: .small)
            }
        }
        .padding(DQ.Spacing.md)
    }

    // MARK: - Helpers

    private var lockLabel: String {
        switch stage {
        case .blurred:   "Photo locked"
        case .partial:   "Revealing"
        case .revealed:  "NameDrop to unlock"
        case .connected: ""
        }
    }

    private var initials: String {
        let parts = name.split(separator: " ")
        if parts.count >= 2 { return "\(parts[0].prefix(1))\(parts[1].prefix(1))".uppercased() }
        return String(name.prefix(1)).uppercased()
    }

    private var accessibilityLabel: String {
        switch stage {
        case .blurred:   "Match photo heavily blurred. Break the ice to reveal."
        case .partial:   "Match photo revealing during the icebreaker, \(Int(progress * 100)) percent clear."
        case .revealed:  "Match photo mostly clear. NameDrop to connect."
        case .connected: "Full profile revealed for \(name)."
        }
    }
}
