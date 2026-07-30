import SwiftUI

/// Why these two matched: the headline vibe score, the four-dimension
/// compatibility breakdown, and the shared-interest chips (§5
/// VibeScoreBreakdown). Shown at stages 1–3; stage 4 replaces it with the
/// rating and tier-upgrade cards.
///
/// §5 also specifies a percentile chip ("Top 4% nearby") beside the label.
/// Nothing in `ScoreBreakdown` or the profile model backs a percentile, so it
/// is omitted rather than fabricated — the number and label sit alone.
struct VibeScoreBreakdown: View {
    /// Overall compatibility, 0…1.
    let overall: Double
    let vibes: [String]
    let breakdown: ScoreBreakdown

    @Environment(\.dq) private var p
    @Environment(\.dqTheme) private var theme

    private var rows: [(label: String, value: Double)] {
        [
            ("Shared interests", breakdown.interestOverlap),
            ("Intent match", breakdown.relationshipTypeMatch),
            ("Age range", breakdown.ageCompatibility),
            ("Preferences", breakdown.preferenceAlignment)
        ]
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            header

            VStack(spacing: DQSpace.tight) {
                ForEach(rows, id: \.label) { row in
                    breakdownRow(row.label, row.value)
                }
            }

            if !vibes.isEmpty {
                FlowLayout(spacing: 7) {
                    ForEach(vibes, id: \.self) { vibe in
                        DQChip(text: vibe)
                    }
                }
                .padding(.top, 3)
            }
        }
        .padding(DQSpace.gutter)
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

    private var header: some View {
        HStack(alignment: .firstTextBaseline, spacing: DQSpace.tight) {
            Text("\(Int((overall * 100).rounded()))")
                .font(DQFont.displayL)
                .tracking(DQFont.trackDisplay)
                .foregroundStyle(p.text)
                .monospacedDigit()

            Text("Vibe match")
                .font(DQFont.labelSized(11))
                .tracking(DQFont.track(11, em: 0.14))
                .textCase(.uppercase)
                .foregroundStyle(p.text2)

            Spacer(minLength: 0)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Vibe match \(Int((overall * 100).rounded())) percent")
    }

    private func breakdownRow(_ label: String, _ value: Double) -> some View {
        let clamped = min(max(value, 0), 1)
        return HStack(spacing: 11) {
            Text(label)
                .font(DQFont.uiSized(11, .semibold))
                .foregroundStyle(p.text2)
                .lineLimit(1)
                .minimumScaleFactor(0.85)
                .frame(width: 96, alignment: .leading)

            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(p.track)
                    Capsule()
                        .fill(p.ember)
                        .frame(width: geo.size.width * clamped)
                }
            }
            .frame(height: DQSize.meterHeight)

            Text("\(Int((clamped * 100).rounded()))%")
                .font(DQFont.uiSized(11, .bold))
                .foregroundStyle(p.text)
                .monospacedDigit()
                .frame(width: 52, alignment: .trailing)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(label) \(Int((clamped * 100).rounded())) percent")
    }
}
