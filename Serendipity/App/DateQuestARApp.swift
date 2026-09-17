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

    /// The user's appearance choice, from Settings. `@AppStorage` reads the same
    /// `UserDefaults` key Settings writes, so the change lands here without a
    /// notification or a shared object.
    @AppStorage(DQAppearance.storageKey) private var appearanceRaw = DQAppearance.system.rawValue

    private var appearance: DQAppearance {
        DQAppearance(rawValue: appearanceRaw) ?? .system
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(authViewModel)
                .environmentObject(locationService)
                .environmentObject(matchManager)
                .environmentObject(alertCapManager)
                .environmentObject(balanceEnforcer)
                // The user's choice drives UIKit; `dqFollowSystemTheme` then reads
                // the resulting colorScheme back into the v2 palette. Order matters
                // — the modifier below has to sit under this one to see it.
                .preferredColorScheme(appearance.preferredColorScheme)
                // The one and only DesignSystem v2 theme binding. Every v2 surface
                // reads `@Environment(\.dq)` and inherits from here — including
                // sheets and full-screen covers. Do not pin per surface.
                .dqFollowSystemTheme()
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
