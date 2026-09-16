// MARK: - SECURITY CHECKLIST COMPLIANCE (see docs/SECURITY_CHECKLIST.md)
// [x] No hardcoded secrets, API keys, or tokens
// [x] Renders server-owned state only — trustLevel, studentIDStatus and the
//     school are all written by Cloud Functions and read-only here
// [x] No student ID image, school email, phone number or extracted document data
//     reaches this view; the verification record it would come from is
//     owner-read-only and is not fetched here
// [x] The school display name is community identity, permitted by
//     DESIGN_SYSTEM.md §8. No neighbourhood, venue, building or geohash.
// [x] No PII logged

import SwiftUI

/// Trust centre (docs/DESIGN_SYSTEM.md §6 row 5): the current tier, the
/// four-segment metallic ladder, a row per tier stating how it is earned, and
/// the closing disclaimer.
///
/// Tiers are never gamified — no medals, stars, XP bars or confetti (§5).
struct TrustCenterView: View {
    let tier: UserProfile.TrustLevel

    /// The user's community, e.g. "UCLA". Shown because on a campus product the
    /// school *is* the first line of the trust story — everything below it is
    /// about proving you belong to that community and are who you say you are.
    var schoolDisplayName: String?

    /// Server-written student ID state, used to say what is still outstanding.
    var studentIDStatus: StudentIDStatus = .none

    /// Nil hides the CTA rather than shipping a pill that goes nowhere.
    var onManageVerification: (() -> Void)?

    @Environment(\.dismiss) private var dismiss
    @Environment(\.dq) private var p
    @Environment(\.dqTheme) private var theme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var glowing = false

    private var tiers: [UserProfile.TrustLevel] { [.bronze, .silver, .gold, .platinum] }

    var body: some View {
        ZStack {
            p.bg.ignoresSafeArea()

            VStack(alignment: .leading, spacing: DQSpace.gutter) {
                topBar
                if let schoolDisplayName, !schoolDisplayName.isEmpty {
                    communityRow(schoolDisplayName)
                }
                currentTierCard
                ladderSection
                disclaimer
                if let onManageVerification {
                    Button("Manage verification", action: onManageVerification)
                        .buttonStyle(.dqNeutral)
                }
            }
            .padding(.top, DQSpace.safeTop)
            .padding(.horizontal, DQSpace.gutter)
            .padding(.bottom, 24)
        }
        .ignoresSafeArea(edges: .top)
    }

    private var topBar: some View {
        HStack(spacing: 12) {
            DQIconButton(symbol: "chevron.left", label: "Back") { dismiss() }
            Text("Trust & verification")
                .font(DQFont.uiSized(20, .heavy))
                .tracking(DQFont.track(20, em: -0.02))
                .foregroundStyle(p.text)
            Spacer(minLength: 0)
        }
    }

    // MARK: - Community

    private func communityRow(_ school: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: "graduationcap.fill")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(p.verify)
            VStack(alignment: .leading, spacing: 3) {
                Text(school)
                    .font(DQFont.uiSized(14, .bold))
                    .foregroundStyle(p.text)
                Text(studentIDStatus.isFaceMatched
                     ? "Verified student. Dating and NameDrop are available."
                     : studentIDStatus.isIDVerified
                       ? "Verified student. Match your ID to your selfie to unlock Dating."
                       : "Add your student ID to start Quest Mode.")
                    .font(DQFont.uiSized(11.5, .medium))
                    .foregroundStyle(p.text2)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 17)
        .padding(.vertical, 15)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: DQRadius.card, style: .continuous).fill(p.surface))
        .overlay(RoundedRectangle(cornerRadius: DQRadius.card, style: .continuous)
            .strokeBorder(p.line, lineWidth: 1))
        .accessibilityElement(children: .combine)
    }

    // MARK: - Current tier

    private var currentTierCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 14) {
                Image(systemName: "diamond.fill")
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(tier.dq.color(p))
                    .frame(width: 54, height: 54)
                    .background(Circle().fill(tier.dq.fill(p, theme)))

                VStack(alignment: .leading, spacing: 5) {
                    Text("Current tier")
                        .font(DQFont.labelSized(9, .semibold))
                        .tracking(DQFont.track(9, em: 0.2))
                        .textCase(.uppercase)
                        .foregroundStyle(p.text3)

                    Text(tier.dq.name)
                        .font(DQFont.uiSized(24, .heavy))
                        .tracking(DQFont.track(24, em: -0.03))
                        .foregroundStyle(tier.dq.color(p))

                    // The mock adds "avg 4.6 over 11 meets"; no aggregate
                    // rating or meet count exists on the profile, so the tier's
                    // own requirement carries the line instead.
                    Text(tier.dq.requirement)
                        .font(DQFont.uiSized(11.5, .medium))
                        .foregroundStyle(p.text2)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
            }

            // Four-segment metallic ladder.
            HStack(spacing: 5) {
                ForEach(tiers, id: \.self) { step in
                    Capsule()
                        .fill(step <= tier ? step.dq.color(p) : p.track)
                        .frame(height: 6)
                }
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Tier \(tier.dq.rawValue + 1) of 4")
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: DQRadius.hero, style: .continuous).fill(p.surface)
        )
        .overlay(
            RoundedRectangle(cornerRadius: DQRadius.hero, style: .continuous)
                .strokeBorder(p.line, lineWidth: 1)
        )
        .shadow(color: tier.dq.color(p).opacity(0.4), radius: glowing ? DQMotion.tierGlowRadius : 0)
        .onAppear {
            guard !reduceMotion else { return }
            withAnimation(.easeInOut(duration: 3.2).repeatForever(autoreverses: true)) {
                glowing = true
            }
        }
    }

    // MARK: - Ladder

    private var ladderSection: some View {
        VStack(alignment: .leading, spacing: 11) {
            Text("How tiers are earned")
                .font(DQFont.labelSized(9, .semibold))
                .tracking(DQFont.track(9, em: 0.2))
                .textCase(.uppercase)
                .foregroundStyle(p.text3)

            ForEach(tiers, id: \.self) { step in
                tierRow(step)
            }
        }
    }

    private func tierRow(_ step: UserProfile.TrustLevel) -> some View {
        let isCurrent = step == tier
        let isEarned = step <= tier
        return HStack(spacing: 14) {
            Image(systemName: "diamond.fill")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(step.dq.color(p))

            VStack(alignment: .leading, spacing: 3) {
                Text(step.dq.name)
                    .font(DQFont.uiSized(14, .bold))
                    .tracking(DQFont.track(14, em: -0.01))
                    .foregroundStyle(p.text)
                Text(step.dq.requirement)
                    .font(DQFont.uiSized(11.5, .medium))
                    .foregroundStyle(p.text2)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 0)

            if isEarned {
                Image(systemName: "checkmark")
                    .font(.system(size: 10, weight: .heavy))
                    .foregroundStyle(p.bg)
                    .frame(width: 20, height: 20)
                    .background(Circle().fill(step.dq.color(p)))
            }
        }
        .padding(.horizontal, 17)
        .padding(.vertical, 15)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: DQRadius.card, style: .continuous).fill(p.surface)
        )
        .overlay(
            // Completed tiers are checked; the current tier is ringed.
            RoundedRectangle(cornerRadius: DQRadius.card, style: .continuous)
                .strokeBorder(isCurrent ? step.dq.color(p) : p.line, lineWidth: isCurrent ? 1.5 : 1)
        )
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(
            "\(step.dq.name). \(step.dq.requirement)."
            + (isCurrent ? " Your current tier." : isEarned ? " Earned." : "")
        )
    }

    // MARK: - Disclaimer
    //
    // Load-bearing copy — verbatim from the spec. Tiers exist to reflect
    // verification, never to rank people or gate their visibility. Do not
    // paraphrase, shorten, or move this below the fold.

    private var disclaimer: some View {
        HStack(alignment: .top, spacing: 11) {
            Text("i")
                .font(DQFont.uiSized(10, .bold))
                .foregroundStyle(p.text3)
                .frame(width: 20, height: 20)
                .overlay(Circle().strokeBorder(p.text3, lineWidth: 1.5))

            Text("Tiers reflect verification and post-meet ratings only. They are never a ranking, and they never affect who sees you.")
                .font(DQFont.uiSized(11.5, .medium))
                .foregroundStyle(p.text2)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, 17)
        .padding(.vertical, 15)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: DQRadius.card, style: .continuous).fill(p.surface2)
        )
        .overlay(
            RoundedRectangle(cornerRadius: DQRadius.card, style: .continuous)
                .strokeBorder(p.line, lineWidth: 1)
        )
        .accessibilityElement(children: .combine)
    }
}
