import SwiftUI

// MARK: - Data Rights View
//
// DesignSystem v2 skin. Both actions still open the same "coming soon" notice;
// nothing about the data pipeline changed.

struct DataRightsView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.dq) private var p
    @State private var showComingSoon = false

    var body: some View {
        ZStack {
            p.bg.ignoresSafeArea()

            ScrollView {
                VStack(alignment: .leading, spacing: DQSpace.gutter) {
                    DQTopBar(title: "Your data rights", style: .pushed, onBack: { dismiss() })

                    Text("Under CCPA and GDPR, you have the right to access, correct, and delete your personal data.")
                        .font(DQFont.body)
                        .foregroundStyle(p.text2)
                        .fixedSize(horizontal: false, vertical: true)

                    DQGroup {
                        DQValueRow(label: "Request my data export") { showComingSoon = true }

                        // Rule 4: destructive reads as `danger` ink on the row.
                        // The filled danger pill belongs only to a confirm step.
                        DQDangerRow(label: "Delete all my data") { showComingSoon = true }
                    }
                }
                .padding(.horizontal, DQSpace.gutter)
                .padding(.top, DQSpace.safeTop)
                .padding(.bottom, DQSpace.gutter)
            }
        }
        .ignoresSafeArea(edges: .top)
        .toolbar(.hidden, for: .navigationBar)
        .alert("Coming Soon", isPresented: $showComingSoon) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("This feature is not yet available.")
        }
    }
}
