import SwiftUI

// MARK: - DesignSystem v2 — icebreaker components (§5, §6 row 2)
//
// All read `@Environment(\.dq)`; no view here names a hex.

/// On-surface trust chip (§5 TierBadge / TrustChip): `surface2` pill, `line`
/// border, diamond glyph in the tier colour. Never a medal, star or XP bar.
struct TrustChip: View {
    let tier: UserProfile.TrustLevel

    @Environment(\.dq) private var p

    var body: some View {
        HStack(spacing: 5) {
            Image(systemName: "diamond.fill")
                .font(.system(size: 8, weight: .semibold))
                .foregroundStyle(tier.dq.color(p))
            Text(tier.dq.name)
                .font(DQFont.labelSized(9))
                .foregroundStyle(p.text2)
        }
        .padding(.horizontal, 9)
        .padding(.vertical, 5)
        .background(Capsule().fill(p.surface2))
        .overlay(Capsule().strokeBorder(p.line, lineWidth: 1))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(tier.dq.name) trust tier")
    }
}

/// Persistent partner strip (§6 row 2). The blurred thumbnail and the live
/// reveal meter keep the unblur visible while a game is on screen — without it
/// the reveal advances invisibly and the icebreaker stops feeling connected to
/// the mechanic it drives.
struct PartnerStrip: View {
    let name: String
    let progress: Double
    let tier: UserProfile.TrustLevel

    @Environment(\.dq) private var p
    @Environment(\.dqTheme) private var theme

    private static let thumbSize: CGFloat = 62

    var body: some View {
        HStack(spacing: 13) {
            PartnerPhotoPlaceholder(initials: name.dqInitials, glyphSize: 26)
                .scaleEffect(DQReveal.thumbLayerScale)
                .blur(radius: DQReveal.blurRadius(for: progress, width: Self.thumbSize))
                .frame(width: Self.thumbSize, height: Self.thumbSize)
                .clipShape(RoundedRectangle(cornerRadius: DQRadius.thumb, style: .continuous))

            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 8) {
                    Text(name)
                        .font(DQFont.uiSized(14, .bold))
                        .tracking(DQFont.track(14, em: -0.01))
                        .foregroundStyle(p.text)
                        .lineLimit(1)
                    TrustChip(tier: tier)
                    Spacer(minLength: 0)
                }
                RevealMeter(progress: progress, style: .onSurface)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: DQRadius.card, style: .continuous)
                .fill(p.surface)
        )
        .overlay(
            RoundedRectangle(cornerRadius: DQRadius.card, style: .continuous)
                .strokeBorder(p.line, lineWidth: 1)
        )
        .dqShadow(.small(theme))
    }
}

/// Round/link progress pips.
struct ProgressPips: View {
    let total: Int
    let filled: Int

    @Environment(\.dq) private var p

    var body: some View {
        HStack(spacing: 5) {
            ForEach(0..<max(total, 0), id: \.self) { index in
                Capsule()
                    .fill(index < filled ? p.ember : p.track)
                    .frame(width: 18, height: 5)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Step \(filled) of \(total)")
    }
}

/// §5 IcebreakerOptionRow. Default carries a mono letter; the selected row gets
/// the ember tint, a 1.5pt ember border and a filled check.
struct IcebreakerOptionRow: View {
    let text: String
    /// A/B/C/D — mono, per §2.
    let letter: String
    let isSelected: Bool
    var isEnabled: Bool = true
    var action: () -> Void

    @Environment(\.dq) private var p

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Text(text)
                    .font(DQFont.uiSized(14, isSelected ? .bold : .semibold))
                    .foregroundStyle(p.text)
                    .multilineTextAlignment(.leading)
                    .frame(maxWidth: .infinity, alignment: .leading)

                if isSelected {
                    Image(systemName: "checkmark")
                        .font(.system(size: 11, weight: .heavy))
                        .foregroundStyle(.white)
                        .frame(width: 22, height: 22)
                        .background(Circle().fill(p.ember))
                } else {
                    Text(letter)
                        .font(DQFont.monoSized(12, .medium))
                        .foregroundStyle(p.text3)
                        .frame(width: 22)
                }
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 16)
            .frame(minHeight: DQSize.minHitTarget)
            .background(
                RoundedRectangle(cornerRadius: DQRadius.row, style: .continuous)
                    .fill(isSelected ? p.emberSoft : p.surface2)
            )
            .overlay(
                RoundedRectangle(cornerRadius: DQRadius.row, style: .continuous)
                    .strokeBorder(isSelected ? p.ember : p.line, lineWidth: isSelected ? 1.5 : 1)
            )
            .contentShape(RoundedRectangle(cornerRadius: DQRadius.row, style: .continuous))
        }
        .buttonStyle(.plain)
        .disabled(!isEnabled)
        .accessibilityLabel(text)
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
    }
}

/// §5 WordChainPill. `open` is the slot currently being linked to.
struct WordChainPill: View {
    enum Owner { case theirs, yours, open }

    let word: String
    let owner: Owner

    @Environment(\.dq) private var p

    var body: some View {
        Text(word)
            .font(DQFont.uiSized(13, owner == .open ? .bold : .semibold))
            .foregroundStyle(p.text)
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(Capsule().fill(owner == .yours ? p.emberSoft : p.surface2))
            .overlay(Capsule().strokeBorder(borderColor, lineWidth: 1))
            .accessibilityLabel(accessibilityText)
    }

    private var borderColor: Color {
        switch owner {
        case .yours: p.emberLine
        case .open:  p.lineStrong
        case .theirs: p.line
        }
    }

    private var accessibilityText: String {
        switch owner {
        case .theirs: "\(word), their word"
        case .yours:  "\(word), your word"
        case .open:   "\(word), link a word to this"
        }
    }
}

/// §6 feedback banner, shown above the CTA after each successful action.
///
/// `neutral` is not in §5 — it exists because a timeout is not a success, and
/// dressing one in `ember` would contradict §1, where ember means progress and
/// correct answers.
struct FeedbackBanner: View {
    enum Kind { case success, neutral }

    let text: String
    var kind: Kind = .success

    @Environment(\.dq) private var p

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: kind == .success ? "checkmark" : "clock")
                .font(.system(size: 10, weight: .heavy))
                .foregroundStyle(kind == .success ? .white : p.text2)
                .frame(width: 20, height: 20)
                .background(Circle().fill(kind == .success ? p.ember : p.track))

            Text(text)
                .font(DQFont.uiSized(11.5, .bold))
                .foregroundStyle(kind == .success ? p.emberText : p.text2)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, 15)
        .padding(.vertical, 12)
        // The mock's 18 sits inside §3's rThumb range (16–18).
        .background(
            RoundedRectangle(cornerRadius: DQRadius.thumb, style: .continuous)
                .fill(kind == .success ? p.emberSoft : p.surface2)
        )
        .overlay(
            RoundedRectangle(cornerRadius: DQRadius.thumb, style: .continuous)
                .strokeBorder(kind == .success ? p.emberLine : p.line, lineWidth: 1)
        )
        .accessibilityElement(children: .combine)
    }
}
