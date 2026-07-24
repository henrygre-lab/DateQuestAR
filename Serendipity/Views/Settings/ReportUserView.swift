import SwiftUI

// MARK: - Report User View

struct ReportUserView: View {
    var reportedUID: String

    @StateObject private var verifier = SafetyVerifier()
    @State private var selectedReason: SafetyVerifier.ReportReason = .fakeProfile
    @State private var details = ""
    @State private var submitted = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: DQ.Spacing.xxl) {
                Text("Report a User")
                    .font(DQ.Typography.sectionHeader())
                    .foregroundStyle(DQ.Colors.textPrimary)

                VStack(alignment: .leading, spacing: DQ.Spacing.xs) {
                    Text("REASON")
                        .font(DQ.Typography.sectionLabel())
                        .foregroundStyle(DQ.Colors.textQuaternary)
                        .tracking(0.5)
                    Picker("Reason", selection: $selectedReason) {
                        ForEach(SafetyVerifier.ReportReason.allCases, id: \.self) {
                            Text($0.rawValue).tag($0)
                        }
                    }
                    .pickerStyle(.menu)
                    .tint(DQ.Colors.accent)
                    .padding(DQ.Spacing.md)
                    .background(DQ.Colors.surfaceCard)
                    .clipShape(RoundedRectangle(cornerRadius: DQ.Radii.medium))
                }

                VStack(alignment: .leading, spacing: DQ.Spacing.xs) {
                    Text("DETAILS")
                        .font(DQ.Typography.sectionLabel())
                        .foregroundStyle(DQ.Colors.textQuaternary)
                        .tracking(0.5)
                    TextEditor(text: $details)
                        .frame(height: 100)
                        .padding(DQ.Spacing.xs)
                        .background(DQ.Colors.surfaceCard)
                        .clipShape(RoundedRectangle(cornerRadius: DQ.Radii.medium))
                        .foregroundStyle(DQ.Colors.textPrimary)
                        .overlay(
                            RoundedRectangle(cornerRadius: DQ.Radii.medium)
                                .stroke(Color.white.opacity(0.06), lineWidth: 1)
                        )
                        .accessibilityLabel("Report details")
                }

                if submitted {
                    Label("Report submitted. Thank you.", systemImage: "checkmark.circle.fill")
                        .foregroundStyle(DQ.Colors.success)
                        .font(DQ.Typography.bodyBold())
                } else {
                    Button("Submit Report") {
                        Task {
                            await verifier.reportUser(reportedUID: reportedUID,
                                                      reason: selectedReason, details: details)
                            submitted = true
                        }
                    }
                    .buttonStyle(.dqPrimary)
                }
                Spacer()
            }
            .padding(DQ.Spacing.xl)
        }
        .dqBackground()
    }
}
