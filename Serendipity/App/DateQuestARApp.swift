import SwiftUI
import Combine
import Firebase
import AppTrackingTransparency
import AdSupport

@main
struct DateQuestARApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @StateObject private var authViewModel = AuthViewModel()
    @StateObject private var locationService = LocationService.shared
    @StateObject private var matchManager = MatchManager.shared
    @StateObject private var alertCapManager = AlertCapManager.shared
    @StateObject private var balanceEnforcer = BalanceEnforcer.shared
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(authViewModel)
                .environmentObject(locationService)
                .environmentObject(matchManager)
                .environmentObject(alertCapManager)
                .environmentObject(balanceEnforcer)
                .preferredColorScheme(.dark)
                // The one and only DesignSystem v2 theme pin. Every v2 surface
                // reads `@Environment(\.dq)` and inherits from here — including
                // sheets and full-screen covers. Do not pin per surface.
                .dqTheme(DQThemePreference.resolved)
                .onAppear {
                    requestTrackingPermission()
                }
                .onChange(of: scenePhase) { _, newPhase in
                    if newPhase == .active {
                        // Record daily login XP when app returns to foreground.
                        // Idempotent — multiple calls in the same day are safe.
                        Task { await XPManager.shared.recordDailyLogin() }
                    }
                }
        }
    }

    private func requestTrackingPermission() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
            ATTrackingManager.requestTrackingAuthorization { _ in }
        }
    }
}
