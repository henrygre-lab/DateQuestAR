import SwiftUI

/// The progressive-reveal photo — the hero interaction of an encounter (§5).
///
/// Layers bottom→top: blurred photo at `scale(1.18)`, the scrim gradient, glass
/// tier chips (plus the radar pulse at stage 1), then the identity line and the
/// reveal meter pinned to the bottom. The whole photo unblurs uniformly — no
/// partial face or eye reveal, ever. Identity is gated behind `.connected`,
/// mirroring the production reveal contract.
///
/// Presentational only; pass plain values.
struct RevealHero: View {
    let name: String
    let age: Int
    let progress: Double
    let stage: RevealStage
    let trust: UserProfile.TrustLevel
    let isIDVerified: Bool
    /// Display-only short code derived from the match id.
    let sessionCode: String

    @Environment(\.dq) private var p
    @Environment(\.dqTheme) private var theme

    var body: some View {
        ZStack {
            photo
            DQScrim.hero
            overlays
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .frame(minHeight: DQSize.heroMinHeight)
        .background(p.surface2)
        .clipShape(RoundedRectangle(cornerRadius: DQRadius.hero, style: .continuous))
        .dqShadow(.standard(theme))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityLabel)
    }

    // MARK: - Photo
    //
    // `layerScale` is what guarantees the blur never shows a soft edge at the
    // card bounds. Shared with the icebreaker partner strip.

    private var photo: some View {
        PartnerPhotoPlaceholder(initials: name.dqInitials)
            .scaleEffect(DQReveal.layerScale)
            .blur(radius: DQReveal.blurRadius(for: progress))
    }

    // MARK: - Overlays

    private var overlays: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .top, spacing: 8) {
                HStack(spacing: 7) {
                    GlassChip(
                        symbol: "diamond.fill",
                        symbolColor: trust.dq.color(p),
                        text: trust.dq.name
                    )
                    if isIDVerified {
                        GlassChip(text: "ID verified", weight: .semibold)
                    }
                }
                Spacer(minLength: 0)
                // Radar pulse is stage 1 only — it reads "someone is near",
                // which stops being news once the icebreaker is running.
                if stage == .blurred {
                    RadarPulse()
                }
            }
            .padding(.horizontal, 14)
            .padding(.top, 14)

            Spacer(minLength: 0)

            VStack(alignment: .leading, spacing: 12) {
                if stage >= .connected {
                    revealedIdentity
                } else {
                    hiddenIdentity
                }
                RevealMeter(progress: progress)
            }
            .padding(.horizontal, DQSpace.gutter)
            .padding(.bottom, 17)
        }
    }

    private var revealedIdentity: some View {
        HStack(spacing: DQSpace.tight) {
            Text("\(name), \(age)")
                .font(DQFont.displayL)
                .tracking(DQFont.trackDisplay)
                .foregroundStyle(DQGlass.ink)
                .lineLimit(1)
                .minimumScaleFactor(0.6)

            // `verify` is reserved for identity verification — only show the
            // check when the partner actually cleared it.
            if isIDVerified {
                Image(systemName: "checkmark")
                    .font(.system(size: 11, weight: .heavy))
                    .foregroundStyle(DQGlass.ink)
                    .frame(width: 22, height: 22)
                    .background(Circle().fill(p.verify))
            }
        }
        .transition(.opacity)
    }

    private var hiddenIdentity: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text("Someone nearby")
                .font(DQFont.displayS)
                .tracking(DQFont.trackDisplayS)
                .foregroundStyle(DQGlass.ink)

            // "Identity locked" over "Session": a bare technical ID says
            // nothing, while this line carries the product promise — the name
            // is deliberately withheld. §6.1 corrected to match.
            HStack(spacing: 0) {
                Text("Identity locked · ")
                    .font(DQFont.labelSized(10, .semibold))
                    .tracking(DQFont.track(10, em: 0.14))
                Text(sessionCode)
                    .font(DQFont.monoSized(10))
                    .tracking(DQFont.track(10, em: 0.14))
            }
            .textCase(.uppercase)
            .foregroundStyle(DQGlass.inkDim)
        }
    }

    // MARK: - Helpers

    private var accessibilityLabel: String {
        let pct = Int((min(max(progress, 0), 1) * 100).rounded())
        switch stage {
        case .blurred:   return "Match photo heavily blurred. Break the ice to reveal. \(trust.dq.name) tier."
        case .partial:   return "Match photo revealing during the icebreaker, \(pct) percent clear."
        case .revealed:  return "Match photo mostly clear, \(pct) percent. NameDrop to connect."
        case .connected: return "Full profile revealed for \(name), \(age). \(trust.dq.name) tier."
        }
    }
}
