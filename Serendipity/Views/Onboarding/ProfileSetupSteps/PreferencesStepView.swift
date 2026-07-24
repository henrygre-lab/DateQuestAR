import SwiftUI

struct PreferencesStepView: View {
    @Binding var selectedInterests: Set<String>
    @Binding var selectedRelationshipTypes: Set<MatchPreferences.RelationshipType>
    @Binding var prefMinAge: Int
    @Binding var prefMaxAge: Int

    let allInterests = ["Hiking", "Coffee", "Travel", "Music", "Art", "Foodie",
                        "Fitness", "Reading", "Gaming", "Yoga", "Cooking", "Dogs"]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: DQ.Spacing.xxl) {
                Group {
                    Text("Relationship Type")
                        .font(DQ.Typography.cardTitle())
                        .foregroundStyle(DQ.Colors.textPrimary)
                    FlowLayout {
                        ForEach(MatchPreferences.RelationshipType.allCases, id: \.self) { type in
                            ChipToggle(label: type.rawValue, isOn: selectedRelationshipTypes.contains(type)) {
                                if selectedRelationshipTypes.contains(type) {
                                    selectedRelationshipTypes.remove(type)
                                } else {
                                    selectedRelationshipTypes.insert(type)
                                }
                            }
                        }
                    }
                }
                Group {
                    Text("Interests")
                        .font(DQ.Typography.cardTitle())
                        .foregroundStyle(DQ.Colors.textPrimary)
                    FlowLayout {
                        ForEach(allInterests, id: \.self) { interest in
                            ChipToggle(label: interest, isOn: selectedInterests.contains(interest)) {
                                if selectedInterests.contains(interest) {
                                    selectedInterests.remove(interest)
                                } else {
                                    selectedInterests.insert(interest)
                                }
                            }
                        }
                    }
                }
                Group {
                    Text("Age Range: \(prefMinAge)\u{2013}\(prefMaxAge)")
                        .font(DQ.Typography.cardTitle())
                        .foregroundStyle(DQ.Colors.textPrimary)
                    Stepper("Min: \(prefMinAge)", value: $prefMinAge, in: 18...prefMaxAge)
                        .foregroundStyle(DQ.Colors.textPrimary)
                    Stepper("Max: \(prefMaxAge)", value: $prefMaxAge, in: prefMinAge...60)
                        .foregroundStyle(DQ.Colors.textPrimary)
                }
            }
        }
    }
}
