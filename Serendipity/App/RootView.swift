// MARK: - SECURITY CHECKLIST COMPLIANCE (see docs/SECURITY_CHECKLIST.md)
// [x] No hardcoded secrets, API keys, or tokens
// [x] Routing is driven entirely by AuthViewModel.appState, which is derived from
//     server-issued fields (schoolId, enrollmentStatus, studentIDStatus). No screen
//     here can be reached by editing client state — the backend would refuse the
//     reads behind it anyway.
// [x] The gates are ordered: school gate, then student ID, then profile setup.
//     There is no path that skips one.
// [x] No PII rendered at this level — this view chooses a screen and nothing else

import SwiftUI

struct RootView: View {
    @EnvironmentObject var authViewModel: AuthViewModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Group {
            switch authViewModel.appState {
            case .loading:
                SplashView()
                    .transition(.opacity)
            case .unauthenticated:
                OnboardingView()
                    .transition(.asymmetric(
                        insertion: .move(edge: .trailing).combined(with: .opacity),
                        removal: .move(edge: .leading).combined(with: .opacity)
                    ))
            case .schoolGate:
                // Gate 1. No community issued yet, so nothing else is reachable.
                SchoolGateView()
                    .transition(.asymmetric(
                        insertion: .move(edge: .trailing).combined(with: .opacity),
                        removal: .move(edge: .leading).combined(with: .opacity)
                    ))
            case .enrollmentReview:
                // Proof submitted. enrollmentStatus is .pending, which grants
                // nothing — this screen is honest about that rather than
                // dropping the user into a half-working app.
                DQEmptyState(
                    symbol: "clock.badge.checkmark",
                    title: "We're checking your enrollment",
                    message: "This usually takes a day. We'll let you know as soon "
                           + "as your campus community is open."
                )
                .padding(DQSpace.gutter)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(DQPalette.dark.bg.ignoresSafeArea())
                .transition(.opacity)
            case .studentIDPending:
                // Gate 2. The community exists; Quest Mode does not, until the
                // student ID card photo + liveness clear.
                StudentIDPendingView()
                    .transition(.asymmetric(
                        insertion: .move(edge: .trailing).combined(with: .opacity),
                        removal: .move(edge: .leading).combined(with: .opacity)
                    ))
            case .onboarding:
                ProfileSetupView()
                    .transition(.asymmetric(
                        insertion: .move(edge: .trailing).combined(with: .opacity),
                        removal: .move(edge: .leading).combined(with: .opacity)
                    ))
            case .waitlisted:
                // Dating-only queue. Every other intent stays open, and
                // WaitlistView says so.
                WaitlistView()
                    .transition(.asymmetric(
                        insertion: .move(edge: .trailing).combined(with: .opacity),
                        removal: .scale(scale: 0.95).combined(with: .opacity)
                    ))
            case .authenticated:
                HomeView()
                    .transition(.asymmetric(
                        insertion: .scale(scale: 0.95).combined(with: .opacity),
                        removal: .opacity
                    ))
            }
        }
        .animation(reduceMotion ? .none : DQ.Anim.stateTransition, value: authViewModel.appState)
    }
}
