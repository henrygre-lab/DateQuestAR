import SwiftUI

/// Shows why two people matched: shared intent vibes plus the four-dimension
/// compatibility breakdown. Presentational — pass the vibe tags and the score.
struct VibeScoreBreakdown: View {
    let vibes: [String]
    let breakdown: ScoreBreakdown

    var body: some View {
        VStack(spacing: DQ.Spacing.lg) {
            if !vibes.isEmpty {
                VStack(spacing: DQ.Spacing.xs) {
                    Text("SHARED VIBES")
                        .font(DQ.Typography.mono(10, weight: .semibold))
                        .foregroundStyle(DQ.Colors.mono600)
                    FlowLayout(spacing: DQ.Spacing.xs) {
                        ForEach(vibes, id: \.self) { vibe in
                            Text(vibe)
                                .font(DQ.Typography.caption())
                                .foregroundStyle(DQ.Colors.signal)
                                .padding(.horizontal, DQ.Spacing.sm)
                                .padding(.vertical, DQ.Spacing.xxs)
                                .background(Capsule().fill(DQ.Colors.signalSubtle))
                        }
                    }
                }
            }

            HStack(spacing: DQ.Spacing.xs) {
                pill("Interests", breakdown.interestOverlap)
                pill("Goals", breakdown.relationshipTypeMatch)
                pill("Age", breakdown.ageCompatibility)
                pill("Prefs", breakdown.preferenceAlignment)
            }
        }
    }

    private func pill(_ label: String, _ value: Double) -> some View {
        VStack(spacing: DQ.Spacing.xxxs) {
            Text("\(Int(value * 100))")
                .font(DQ.Typography.mono(19, weight: .bold))
                .foregroundStyle(DQ.Colors.mono900)
            Text(label)
                .font(DQ.Typography.mono(9.5, weight: .medium))
                .foregroundStyle(DQ.Colors.mono600)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, DQ.Spacing.md)
        .background(RoundedRectangle(cornerRadius: DQ.Radii.medium).fill(DQ.Colors.mono100))
        .overlay(RoundedRectangle(cornerRadius: DQ.Radii.medium).stroke(DQ.Colors.mono300, lineWidth: 1))
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(label) \(Int(value * 100)) percent")
    }
}
