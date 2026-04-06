import SwiftUI
import Firebase
import AppTrackingTransparency
import AdSupport

struct DateQuestARApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @StateObject private var authViewModel = AuthViewModel()
    @StateObject private var locationService = LocationService.shared
    @StateObject private var matchManager = MatchManager.shared

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(authViewModel)
                .environmentObject(locationService)
                .environmentObject(matchManager)
                .preferredColorScheme(.dark)
                .onAppear {
                    requestTrackingPermission()
                }
        }
    }

    private func requestTrackingPermission() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
            ATTrackingManager.requestTrackingAuthorization { _ in }
        }
    }
}
