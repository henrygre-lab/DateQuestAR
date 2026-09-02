// MARK: - SECURITY CHECKLIST COMPLIANCE (see docs/SECURITY_CHECKLIST.md)
// [x] No hardcoded secrets, API keys, or tokens
// [x] Dating is offered only when the account can actually use it — the toggle is
//     disabled without the student ID <-> liveness face match and a verified adult
//     age, both server-written fields this view only reads
// [x] Selecting intents here changes local state only. The write goes through the
//     setActiveIntents Cloud Function, which is what starts the 24h Dating-off
//     cooldown; firestore.rules rejects a direct client write to activeIntents.
// [x] No PII rendered — interests and intents are closed sets, not free text

import SwiftUI

struct PreferencesStepView: View {
    @Binding var selectedInterests: Set<String>
    @Binding var selectedIntents: Set<Intent>
    @Binding var prefMinAge: Int
    @Binding var prefMaxAge: Int

    /// Whether this account has cleared the Dating gate. Read-only: it comes from
    /// `UserProfile.canUseDatingIntent`, which reads server-written fields.
    var canUseDating: Bool = false

    @Environment(\.dq) private var p

    let allInterests = ["Hiking", "Coffee", "Travel", "Music", "Art", "Foodie",
                        "Fitness", "Reading", "Gaming", "Yoga", "Cooking", "Dogs"]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: DQSpace.gutter) {
                VStack(alignment: .leading, spacing: DQSpace.tight) {
                    DQSectionHeader(title: "What are you here for?")

                    Text("Pick as many as you like. You can change these any time.")
                        .font(DQFont.bodyS)
                        .foregroundStyle(p.text2)
                        .padding(.horizontal, DQFormMetrics.inset)

                    FlowLayout(spacing: 7) {
                        ForEach(Intent.allCases) { intent in
                            let isLocked = intent.requiresFaceMatch && !canUseDating
                            chip(intent.displayName,
                                 selected: selectedIntents.contains(intent),
                                 disabled: isLocked) {
                                if selectedIntents.contains(intent) {
                                    selectedIntents.remove(intent)
                                } else {
                                    selectedIntents.insert(intent)
                                }
                            }
                        }
                    }

                    // Dating is one intent among five, and the only one that needs
                    // the face match. Saying so here is better than a chip that
                    // silently does nothing when tapped.
                    DQFootnote(text: canUseDating
                               ? "Dating is optional and off unless you pick it."
                               : "Dating needs your student ID and selfie to match. "
                                 + "Everything else is open now.")
                }

                VStack(alignment: .leading, spacing: DQSpace.tight) {
                    DQSectionHeader(title: "Interests")
                    FlowLayout(spacing: 7) {
                        ForEach(allInterests, id: \.self) { interest in
                            chip(interest, selected: selectedInterests.contains(interest)) {
                                if selectedInterests.contains(interest) {
                                    selectedInterests.remove(interest)
                                } else {
                                    selectedInterests.insert(interest)
                                }
                            }
                        }
                    }
                }

                VStack(spacing: 0) {
                    DQSectionHeader(title: "Age range")
                    DQGroup {
                        DQStepperRow(
                            label: "Minimum",
                            value: $prefMinAge,
                            range: 18...prefMaxAge
                        )
                        DQStepperRow(
                            label: "Maximum",
                            value: $prefMaxAge,
                            range: prefMinAge...60
                        )
                    }
                }
            }
        }
    }

    private func chip(_ title: String,
                      selected: Bool,
                      disabled: Bool = false,
                      action: @escaping () -> Void) -> some View {
        Button(action: action) {
            DQChip(text: title, selected: selected)
                .frame(minHeight: DQSize.minHitTarget)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(disabled)
        .opacity(disabled ? 0.45 : 1)
        .accessibilityLabel(title)
        .accessibilityHint(disabled ? "Needs student ID verification" : "")
        .accessibilityAddTraits(selected ? [.isButton, .isSelected] : .isButton)
    }
}
