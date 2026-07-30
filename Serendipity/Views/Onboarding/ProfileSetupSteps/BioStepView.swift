import SwiftUI

struct BioStepView: View {
    @Binding var displayName: String
    @Binding var bio: String
    @Binding var age: Int
    @Binding var selectedGender: Gender
    @Environment(\.dq) private var p
    @State private var ageText: String = ""

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: DQSpace.gutter) {
                DQTextField(
                    label: "Display name",
                    placeholder: "Display Name",
                    text: $displayName
                )

                // Age stays typed, not stepped — same interaction as before.
                DQGroup {
                    DQRow(label: "Age") {
                        TextField("Age", text: $ageText)
                            .keyboardType(.numberPad)
                            .multilineTextAlignment(.trailing)
                            .font(DQFont.monoSized(15, .medium))
                            .foregroundStyle(p.text)
                            .tint(p.text)
                            .frame(width: 60)
                            .onChange(of: ageText) { _, newValue in
                                let digits = newValue.filter(\.isNumber)
                                if let parsed = Int(digits) {
                                    age = min(99, max(18, parsed))
                                }
                                if digits != newValue { ageText = digits }
                            }
                    }
                    .accessibilityLabel("Age")
                    .accessibilityValue("\(age) years old")
                }
                .onAppear { ageText = "\(age)" }

                VStack(alignment: .leading, spacing: DQSpace.tight) {
                    DQSectionHeader(title: "Gender")
                    FlowLayout(spacing: 7) {
                        ForEach(Gender.allCases, id: \.self) { gender in
                            Button { selectedGender = gender } label: {
                                DQChip(text: gender.displayLabel, selected: selectedGender == gender)
                                    .frame(minHeight: DQSize.minHitTarget)
                                    .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel(gender.displayLabel)
                            .accessibilityAddTraits(
                                selectedGender == gender ? [.isButton, .isSelected] : .isButton
                            )
                        }
                    }
                }

                DQTextArea(
                    label: "Bio",
                    placeholder: "Write a short bio…",
                    text: $bio,
                    characterLimit: 500
                )
                .accessibilityLabel("Bio")
            }
        }
    }
}
