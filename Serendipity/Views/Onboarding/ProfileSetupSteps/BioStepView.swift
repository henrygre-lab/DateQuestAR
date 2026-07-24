import SwiftUI

struct BioStepView: View {
    @Binding var displayName: String
    @Binding var bio: String
    @Binding var age: Int
    @Binding var selectedGender: Gender
    @State private var ageText: String = ""

    var body: some View {
        ScrollView {
            VStack(spacing: DQ.Spacing.xl) {
                DQTextField(label: "Display name",
                            placeholder: "Display Name", text: $displayName,
                            isSecure: false)
                HStack {
                    Text("Age")
                        .foregroundStyle(DQ.Colors.textPrimary)
                    Spacer()
                    TextField("Age", text: $ageText)
                        .keyboardType(.numberPad)
                        .multilineTextAlignment(.trailing)
                        .frame(width: 60)
                        .foregroundStyle(DQ.Colors.textPrimary)
                        .onChange(of: ageText) { _, newValue in
                            let digits = newValue.filter(\.isNumber)
                            if let parsed = Int(digits) {
                                age = min(99, max(18, parsed))
                            }
                            if digits != newValue { ageText = digits }
                        }
                }
                .padding()
                .background(DQ.Colors.surfaceElevated)
                .clipShape(RoundedRectangle(cornerRadius: DQ.Radii.medium))
                .accessibilityLabel("Age")
                .accessibilityValue("\(age) years old")
                .onAppear { ageText = "\(age)" }

                // Gender selection
                VStack(alignment: .leading, spacing: DQ.Spacing.sm) {
                    Text("Gender")
                        .font(DQ.Typography.cardTitle())
                        .foregroundStyle(DQ.Colors.textPrimary)
                    FlowLayout {
                        ForEach(Gender.allCases, id: \.self) { gender in
                            ChipToggle(
                                label: gender.displayLabel,
                                isOn: selectedGender == gender
                            ) {
                                selectedGender = gender
                            }
                        }
                    }
                }

                TextEditor(text: $bio)
                    .frame(height: 100)
                    .padding(DQ.Spacing.xs)
                    .background(DQ.Colors.surfaceElevated)
                    .clipShape(RoundedRectangle(cornerRadius: DQ.Radii.medium))
                    .foregroundStyle(DQ.Colors.textPrimary)
                    .overlay(alignment: .topLeading) {
                        if bio.isEmpty {
                            Text("Write a short bio\u{2026}")
                                .foregroundStyle(DQ.Colors.textPlaceholder)
                                .padding(DQ.Spacing.md)
                        }
                    }
                    .accessibilityLabel("Bio")
                    .accessibilityHint(bio.isEmpty ? "Write a short bio about yourself" : "\(bio.count) characters entered")
            }
        }
    }
}
