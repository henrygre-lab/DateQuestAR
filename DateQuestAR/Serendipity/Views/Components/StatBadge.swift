import SwiftUI

struct StatBadge: View {
    var icon: String
    var value: String
    var label: String
    var color: Color

    var body: some View {
        VStack(spacing: DQ.Spacing.xs) {
            ZStack {
                Circle()
                    .fill(color.opacity(0.15))
                    .frame(width: 40, height: 40)
                Image(systemName: icon)
                    .font(.system(size: 16, weight: .medium))
                    .foregroundStyle(color)
            }
            Text(value)
                .font(.system(size: 24, weight: .bold, design: .rounded))
                .foregroundStyle(DQ.Colors.textPrimary)
            Text(label.uppercased())
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(Color(hex: "#9CA3AF"))
                .tracking(0.5)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, DQ.Spacing.lg)
        .background(Color(white: 0.08))
        .clipShape(RoundedRectangle(cornerRadius: DQ.Radii.large))
        .overlay(
            RoundedRectangle(cornerRadius: DQ.Radii.large)
                .stroke(Color.white.opacity(0.06), lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.12), radius: 6, x: 0, y: 2)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(label): \(value)")
    }
}
