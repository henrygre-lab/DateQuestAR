import SwiftUI

// MARK: - Data Rights View

struct DataRightsView: View {
    @State private var showComingSoon = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: DQ.Spacing.xxl) {
                Text("Your Data Rights")
                    .font(DQ.Typography.sectionHeader())
                    .foregroundStyle(DQ.Colors.textPrimary)
                Text("Under CCPA and GDPR, you have the right to access, correct, and delete your personal data.")
                    .font(DQ.Typography.body())
                    .foregroundStyle(DQ.Colors.textSecondary)
                Button("Request My Data Export") { showComingSoon = true }
                    .buttonStyle(.dqSecondary)
                Button("Delete All My Data") { showComingSoon = true }
                    .buttonStyle(.dqSecondary)
            }
            .padding(DQ.Spacing.xl)
        }
        .dqBackground()
        .alert("Coming Soon", isPresented: $showComingSoon) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("This feature is not yet available.")
        }
    }
}
