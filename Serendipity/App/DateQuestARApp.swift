import SwiftUI
import Firebase
import AppTrackingTransparency
import AdSupport

struct DateQuestARApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @StateObject private var authViewModel = AuthViewModel()
    @StateObject private var locationService = LocationService.shared
    @StateObject private var matchManager = MatchManager.shared
    @StateObject private var balanceEnforcer = BalanceEnforcer.shared
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(authViewModel)
                .environmentObject(locationService)
                .environmentObject(matchManager)
                .environmentObject(balanceEnforcer)
                .preferredColorScheme(.dark)
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
