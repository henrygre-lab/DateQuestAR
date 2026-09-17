import SwiftUI

/// Four-segment progress indicator for the encounter reveal ladder:
/// Nearby → Icebreaker → Revealed → Connected (§5 StageStepper).
/// Completed and current segments are `signal`; the current one also carries the
/// signal glow. Presentational only — pass the current `RevealStage`.
struct StageStepper: View {
    let current: RevealStage

    @Environment(\.dq) private var p

    private var stages: [DQReveal.Stage] { DQReveal.Stage.allCases }

    var body: some View {
        VStack(spacing: 8) {
            HStack(spacing: 6) {
                ForEach(stages, id: \.rawValue) { stage in
                    Capsule()
                        .fill(reached(stage) ? p.signal : p.track)
                        .frame(height: DQSize.stepperHeight)
                        // §5: the current segment gets a 12px glow, now in signal.
                        .shadow(color: isCurrent(stage) ? p.signalGlow : .clear, radius: 6)
                }
            }

            HStack(spacing: 6) {
                ForEach(stages, id: \.rawValue) { stage in
                    Text(stage.title)
                        .font(DQFont.labelSized(8.5))
                        .tracking(DQFont.track(8.5, em: 0.08))
                        .textCase(.uppercase)
                        .foregroundStyle(reached(stage) ? p.signalText : p.text3)
                        .lineLimit(1)
                        .minimumScaleFactor(0.85)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(
            "Stage \(current.dq.title), step \(current.dq.rawValue) of \(stages.count)"
        )
    }

    private func reached(_ stage: DQReveal.Stage) -> Bool {
        stage.rawValue <= current.dq.rawValue
    }

    private func isCurrent(_ stage: DQReveal.Stage) -> Bool {
        stage == current.dq
    }
}
