// MARK: - SECURITY CHECKLIST COMPLIANCE (see docs/SECURITY_CHECKLIST.md)
// [x] No hardcoded secrets, API keys, or tokens
// [x] Hosts StudentIDStepView; the verification decision is the server's and this
//     view only re-reads the profile once the server has answered
// [x] No student ID image or extracted document data reaches this view
// [x] No PII rendered — the school display name is community identity, which
//     DESIGN_SYSTEM.md §8 permits; no neighbourhood, venue or building
// [x] Design system: v2 (DQFormParts, @Environment(\.dq)) — no v1 tokens

import SwiftUI

// MARK: - StudentIDPendingView

/// The screen between the school gate and the rest of the app.
///
/// The user is in their community — they can see their school's name — but Quest
/// Mode stays shut until the student ID card photo and liveness check clear.
struct StudentIDPendingView: View {
    @EnvironmentObject private var authViewModel: AuthViewModel
    @StateObject private var verifier = SafetyVerifier()
    @Environment(\.dq) private var p

    var body: some View {
        ZStack {
            p.bg.ignoresSafeArea()

            VStack(spacing: 0) {
                DQTopBar(title: communityTitle, style: .root)

                ScrollView {
                    StudentIDStepView(
                        verifier: verifier,
                        profileAge: authViewModel.currentUser?.age ?? 0,
                        onVerified: { Task { await authViewModel.reloadProfile() } }
                    )
                    .padding(.horizontal, DQSpace.gutter)
                    .padding(.top, DQSpace.block)
                    .padding(.bottom, DQSpace.safeBottom)
                }
            }
        }
    }

    /// "Quest Mode · UCLA" is the one place-shaped string the design system
    /// allows: it is community identity, not a location. Falls back to the plain
    /// title rather than inventing a name.
    private var communityTitle: String {
        guard let school = authViewModel.currentUser?.schoolDisplayName, !school.isEmpty else {
            return "One more step"
        }
        return "One more step · \(school)"
    }
}
