import SwiftUI

// MARK: - Vibe Step

struct VibeStepView: View {
    @Binding var selectedVibes: Set<String>

    let allVibes = [
        "Chill hangout", "Deep conversation", "Adventure buddy",
        "Coffee date", "Group outing", "Creative collab",
        "Workout partner", "Foodie crawl", "Night out",
        "Study buddy", "Dog walk", "Just vibing"
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: DQ.Spacing.xl) {
            Text("What kind of connection are you looking for right now?")
                .font(DQ.Typography.body())
                .foregroundStyle(DQ.Colors.textSecondary)

            Text("Select all that match your vibe. This helps us find compatible matches nearby.")
                .font(DQ.Typography.caption())
                .foregroundStyle(DQ.Colors.textTertiary)

            FlowLayout {
                ForEach(allVibes, id: \.self) { vibe in
                    ChipToggle(label: vibe, isOn: selectedVibes.contains(vibe)) {
                        if selectedVibes.contains(vibe) {
                            selectedVibes.remove(vibe)
                        } else {
                            selectedVibes.insert(vibe)
                        }
                    }
                }
            }

            if !selectedVibes.isEmpty {
                Text("\(selectedVibes.count) vibe(s) selected")
                    .font(DQ.Typography.caption())
                    .foregroundStyle(DQ.Colors.accent)
            }
        }
    }
}
