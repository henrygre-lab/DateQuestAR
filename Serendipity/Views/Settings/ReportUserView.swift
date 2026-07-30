import SwiftUI

// MARK: - Report User View
//
// DesignSystem v2 skin. The report submitted to `SafetyVerifier` is unchanged:
// same reasons, same details field, same call.

struct ReportUserView: View {
    var reportedUID: String

    @Environment(\.dismiss) private var dismiss
    @Environment(\.dq) private var p
    @StateObject private var verifier = SafetyVerifier()
    @State private var selectedReason: SafetyVerifier.ReportReason = .fakeProfile
    @State private var details = ""
    @State private var submitted = false

    var body: some View {
        ZStack {
            p.bg.ignoresSafeArea()

            ScrollView {
                VStack(alignment: .leading, spacing: DQSpace.gutter) {
                    DQTopBar(title: "Report a user", style: .pushed, onBack: { dismiss() })

                    VStack(spacing: 0) {
                        DQSectionHeader(title: "Reason")
                        DQGroup {
                            // Six reasons is past the 2–3 a segmented picker
                            // takes, so the choice opens as a menu on a row.
                            Menu {
                                ForEach(SafetyVerifier.ReportReason.allCases, id: \.self) { reason in
                                    Button(reason.rawValue) { selectedReason = reason }
                                }
                            } label: {
                                DQRow(label: "Reason") {
                                    HStack(spacing: DQSpace.tight) {
                                        // A reason is a word, not a value — §2
                                        // keeps it in Jakarta.
                                        Text(selectedReason.rawValue)
                                            .font(DQFont.uiSized(13, .medium))
                                            .foregroundStyle(p.text2)
                                        Image(systemName: "chevron.up.chevron.down")
                                            .font(.system(size: 12, weight: .semibold))
                                            .foregroundStyle(p.text3)
                                    }
                                }
                            }
                            .accessibilityLabel("Reason")
                            .accessibilityValue(selectedReason.rawValue)
                        }
                    }

                    DQTextArea(
                        label: "Details",
                        placeholder: "What happened?",
                        text: $details
                    )
                    .accessibilityLabel("Report details")

                    if submitted {
                        HStack(spacing: DQSpace.tight) {
                            Image(systemName: "checkmark")
                                .font(.system(size: 10, weight: .heavy))
                                .foregroundStyle(.white)
                                .frame(width: 20, height: 20)
                                .background(Circle().fill(p.cta))
                            Text("Report submitted. Thank you.")
                                .font(DQFont.uiSized(13, .semibold))
                                .foregroundStyle(p.text)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .accessibilityElement(children: .combine)
                    } else {
                        Button("Submit report") {
                            Task {
                                await verifier.reportUser(
                                    reportedUID: reportedUID,
                                    reason: selectedReason,
                                    details: details
                                )
                                submitted = true
                            }
                        }
                        .buttonStyle(.dqNeutral)
                    }

                    Spacer(minLength: 0)
                }
                .padding(.horizontal, DQSpace.gutter)
                .padding(.top, DQSpace.safeTop)
                .padding(.bottom, DQSpace.gutter)
            }
        }
        .ignoresSafeArea(edges: .top)
        .toolbar(.hidden, for: .navigationBar)
    }
}
