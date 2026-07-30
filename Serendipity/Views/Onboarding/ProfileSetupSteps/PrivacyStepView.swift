import SwiftUI

struct PrivacyStepView: View {
    @Binding var alertLimit: Int
    @Binding var locationMode: PrivacySettings.LocationSharingMode

    @Environment(\.dq) private var p

    var body: some View {
        VStack(alignment: .leading, spacing: DQSpace.gutter) {
            Text("Your location is always anonymized using geohashing — exact coordinates are never shared.")
                .font(DQFont.body)
                .foregroundStyle(p.text2)
                .fixedSize(horizontal: false, vertical: true)

            DQGroup {
                DQStepperRow(
                    label: "Max alerts per day",
                    value: $alertLimit,
                    range: 1...20
                )
            }

            // Segmented pickers stand alone, never inside a group.
            VStack(alignment: .leading, spacing: 7) {
                DQSectionHeader(title: "Location mode")
                DQSegmentedPicker(
                    options: [PrivacySettings.LocationSharingMode.anonymized, .hidden],
                    title: { $0 == .anonymized ? "Anonymized" : "Hidden" },
                    selection: $locationMode
                )
            }

            VerificationUpsellCard()

            DQFootnote(text: "You can add auto-pause zones (Home, Work) in Settings after onboarding.")
        }
    }
}
