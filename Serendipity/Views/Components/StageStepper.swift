import SwiftUI

/// Four-node progress indicator for the encounter reveal flow:
/// Nearby → Icebreaker → Revealed → Connected. Presentational only — pass the
/// current `RevealStage`. High-contrast mono + a single signal accent.
struct StageStepper: View {
    let current: RevealStage

    private struct Node { let label: String; let stage: RevealStage }
    private let nodes: [Node] = [
        .init(label: "Nearby", stage: .blurred),
        .init(label: "Icebreaker", stage: .partial),
        .init(label: "Revealed", stage: .revealed),
        .init(label: "Connected", stage: .connected)
    ]

    var body: some View {
        HStack(alignment: .top, spacing: 0) {
            ForEach(Array(nodes.enumerated()), id: \.offset) { index, node in
                dot(node)
                if index < nodes.count - 1 {
                    connector(filled: current > node.stage)
                }
            }
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Stage \(currentLabel), step \(currentIndex + 1) of \(nodes.count)")
    }

    private func dot(_ node: Node) -> some View {
        let reached = current >= node.stage
        let isCurrent = current == node.stage
        return VStack(spacing: DQ.Spacing.xs) {
            ZStack {
                if isCurrent {
                    Circle()
                        .stroke(DQ.Colors.signalMuted, lineWidth: 2)
                        .frame(width: 22, height: 22)
                }
                Circle()
                    .fill(reached ? DQ.Colors.signal : DQ.Colors.mono300)
                    .frame(width: 11, height: 11)
            }
            .frame(height: 22)

            Text(node.label)
                .font(DQ.Typography.mono(9.5, weight: isCurrent ? .bold : .medium))
                .foregroundStyle(reached ? DQ.Colors.mono900 : DQ.Colors.mono600)
                .fixedSize()
        }
        .frame(maxWidth: .infinity)
    }

    private func connector(filled: Bool) -> some View {
        Rectangle()
            .fill(filled ? DQ.Colors.signal : DQ.Colors.mono300)
            .frame(height: 2)
            .frame(maxWidth: .infinity)
            .padding(.top, 10)
    }

    private var currentIndex: Int {
        nodes.firstIndex { $0.stage == current } ?? 0
    }

    private var currentLabel: String {
        nodes.first { $0.stage == current }?.label ?? "Nearby"
    }
}
