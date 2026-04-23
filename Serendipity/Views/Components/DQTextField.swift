import SwiftUI

struct DQTextField: View {
    var label: String = ""
    var placeholder: String
    @Binding var text: String
    var isSecure: Bool
    var errorMessage: String? = nil
    var keyboardType: UIKeyboardType = .default

    @FocusState private var isFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: DQ.Spacing.xxxs) {
            Group {
                if isSecure {
                    SecureField(placeholder, text: $text)
                } else {
                    TextField(placeholder, text: $text)
                        .keyboardType(keyboardType)
                        .autocapitalization(.none)
                }
            }
            .focused($isFocused)
            .padding()
            .frame(height: DQ.Sizing.buttonHeight)
            .background(DQ.Colors.surfaceElevated)
            .foregroundStyle(DQ.Colors.textPrimary)
            .clipShape(RoundedRectangle(cornerRadius: DQ.Radii.medium))
            .overlay(
                RoundedRectangle(cornerRadius: DQ.Radii.medium)
                    .stroke(borderColor, lineWidth: DQ.Sizing.strokeWidth)
            )
            .accessibilityLabel(label.isEmpty ? placeholder : label)
            .accessibilityValue(text.isEmpty ? "empty" : text)

            if let errorMessage {
                Text(errorMessage)
                    .font(DQ.Typography.captionSmall())
                    .foregroundStyle(DQ.Colors.error)
                    .accessibilityLabel("Error: \(errorMessage)")
            }
        }
    }

    private var borderColor: Color {
        if errorMessage != nil { return DQ.Colors.error }
        if isFocused { return DQ.Colors.accent }
        return DQ.Colors.accentSecondary
    }
}
