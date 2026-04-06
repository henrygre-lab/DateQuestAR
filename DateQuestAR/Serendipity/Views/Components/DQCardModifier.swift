import SwiftUI

struct DQCardModifier: ViewModifier {
    var cornerRadius: CGFloat = DQ.Radii.xl
    var backgroundColor: Color = DQ.Colors.surfaceCard
    var strokeColor: Color = .clear
    var strokeWidth: CGFloat = DQ.Sizing.strokeWidth

    func body(content: Content) -> some View {
        content
            .padding(DQ.Spacing.xl)
            .background(backgroundColor)
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius))
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius)
                    .stroke(strokeColor, lineWidth: strokeWidth)
            )
    }
}

extension View {
    func dqCard(
        cornerRadius: CGFloat = DQ.Radii.xl,
        background: Color = DQ.Colors.surfaceCard,
        stroke: Color = .clear,
        strokeWidth: CGFloat = DQ.Sizing.strokeWidth
    ) -> some View {
        modifier(DQCardModifier(
            cornerRadius: cornerRadius,
            backgroundColor: background,
            strokeColor: stroke,
            strokeWidth: strokeWidth
        ))
    }
}
