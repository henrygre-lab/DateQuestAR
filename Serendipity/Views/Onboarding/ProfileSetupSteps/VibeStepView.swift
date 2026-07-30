import SwiftUI

// MARK: - Vibe Step

struct VibeStepView: View {
    @Binding var selectedVibes: Set<String>
    @Environment(\.dq) private var p

    let allVibes = [
        "Chill hangout", "Deep conversation", "Adventure buddy",
        "Coffee date", "Group outing", "Creative collab",
        "Workout partner", "Foodie crawl", "Night out",
        "Study buddy", "Dog walk", "Just vibing"
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: DQSpace.gutter) {
            Text("What kind of connection are you looking for right now?")
                .font(DQFont.body)
                .foregroundStyle(p.text2)
                .fixedSize(horizontal: false, vertical: true)

            Text("Select all that match your vibe. This helps us find compatible matches nearby.")
                .font(DQFont.bodyS)
                .foregroundStyle(p.text3)
                .fixedSize(horizontal: false, vertical: true)

            FlowLayout(spacing: 7) {
                ForEach(allVibes, id: \.self) { vibe in
                    Button {
                        if selectedVibes.contains(vibe) {
                            selectedVibes.remove(vibe)
                        } else {
                            selectedVibes.insert(vibe)
                        }
                    } label: {
                        DQChip(text: vibe, selected: selectedVibes.contains(vibe))
                            .frame(minHeight: DQSize.minHitTarget)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(vibe)
                    .accessibilityAddTraits(
                        selectedVibes.contains(vibe) ? [.isButton, .isSelected] : .isButton
                    )
                }
            }

            if !selectedVibes.isEmpty {
                Text("\(selectedVibes.count)")
                    .font(DQFont.monoSized(13, .medium))
                    .foregroundStyle(p.text3)
                    .accessibilityLabel("\(selectedVibes.count) vibes selected")
            }
        }
    }
}
