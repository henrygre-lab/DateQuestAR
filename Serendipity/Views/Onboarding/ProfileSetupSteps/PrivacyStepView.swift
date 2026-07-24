import SwiftUI

struct PrivacyStepView: View {
    @Binding var alertLimit: Int
    @Binding var locationMode: PrivacySettings.LocationSharingMode

    var body: some View {
        VStack(alignment: .leading, spacing: DQ.Spacing.xxl) {
            Text("Your location is always anonymized using geohashing \u{2014} exact coordinates are never shared.")
                .foregroundStyle(DQ.Colors.textSecondary)
            Stepper("Max alerts/day: \(alertLimit)", value: $alertLimit, in: 1...20)
                .foregroundStyle(DQ.Colors.textPrimary)
            Picker("Location Mode", selection: $locationMode) {
                Text("Anonymized (Recommended)").tag(PrivacySettings.LocationSharingMode.anonymized)
                Text("Hidden").tag(PrivacySettings.LocationSharingMode.hidden)
            }
            .pickerStyle(.segmented)

            // Verification upsell
            VerificationUpsellCard()

            Text("You can add auto-pause zones (Home, Work) in Settings after onboarding.")
                .font(DQ.Typography.footnote())
                .foregroundStyle(DQ.Colors.textQuaternary)
        }
    }
}
