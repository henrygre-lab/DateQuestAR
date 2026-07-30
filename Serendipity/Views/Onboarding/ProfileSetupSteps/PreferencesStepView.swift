import SwiftUI

struct PreferencesStepView: View {
    @Binding var selectedInterests: Set<String>
    @Binding var selectedRelationshipTypes: Set<MatchPreferences.RelationshipType>
    @Binding var prefMinAge: Int
    @Binding var prefMaxAge: Int

    @Environment(\.dq) private var p

    let allInterests = ["Hiking", "Coffee", "Travel", "Music", "Art", "Foodie",
                        "Fitness", "Reading", "Gaming", "Yoga", "Cooking", "Dogs"]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: DQSpace.gutter) {
                VStack(alignment: .leading, spacing: DQSpace.tight) {
                    DQSectionHeader(title: "Relationship type")
                    FlowLayout(spacing: 7) {
                        ForEach(MatchPreferences.RelationshipType.allCases, id: \.self) { type in
                            chip(type.rawValue, selected: selectedRelationshipTypes.contains(type)) {
                                if selectedRelationshipTypes.contains(type) {
                                    selectedRelationshipTypes.remove(type)
                                } else {
                                    selectedRelationshipTypes.insert(type)
                                }
                            }
                        }
                    }
                }

                VStack(alignment: .leading, spacing: DQSpace.tight) {
                    DQSectionHeader(title: "Interests")
                    FlowLayout(spacing: 7) {
                        ForEach(allInterests, id: \.self) { interest in
                            chip(interest, selected: selectedInterests.contains(interest)) {
                                if selectedInterests.contains(interest) {
                                    selectedInterests.remove(interest)
                                } else {
                                    selectedInterests.insert(interest)
                                }
                            }
                        }
                    }
                }

                VStack(spacing: 0) {
                    DQSectionHeader(title: "Age range")
                    DQGroup {
                        DQStepperRow(
                            label: "Minimum",
                            value: $prefMinAge,
                            range: 18...prefMaxAge
                        )
                        DQStepperRow(
                            label: "Maximum",
                            value: $prefMaxAge,
                            range: prefMinAge...60
                        )
                    }
                }
            }
        }
    }

    private func chip(_ title: String, selected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            DQChip(text: title, selected: selected)
                .frame(minHeight: DQSize.minHitTarget)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(title)
        .accessibilityAddTraits(selected ? [.isButton, .isSelected] : .isButton)
    }
}
