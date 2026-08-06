import UIKit
import FirebaseCore
import GoogleSignIn
import UserNotifications
import CoreBluetooth

class AppDelegate: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate {

    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        // Firebase configuration
        configureFirebase()

        // Push notifications
        UNUserNotificationCenter.current().delegate = self
        requestNotificationPermissions()

        return true
    }

    // MARK: - Firebase Setup

    private func configureFirebase() {
        guard Bundle.main.path(forResource: "GoogleService-Info", ofType: "plist") != nil else {
            Log.app.error(
                "GoogleService-Info.plist not found — Firebase will not be initialized. "
                + "Download it from https://console.firebase.google.com/"
            )
            return
        }

        FirebaseApp.configure()
        Log.app.debug("Firebase configured successfully")
    }

    // MARK: - Notifications

    private func requestNotificationPermissions() {
        UNUserNotificationCenter.current().requestAuthorization(
            options: [.alert, .badge, .sound]
        ) { granted, error in
            if let error = error {
                Log.app.error("Notification permission error: \(error.localizedDescription)")
            }
            Log.app.debug("Notifications granted: \(granted)")
        }
    }

    func application(_ application: UIApplication,
                     didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data) {
        // TODO: Forward token to Firebase Messaging
        // Messaging.messaging().apnsToken = deviceToken
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                willPresent notification: UNNotification,
                                withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        completionHandler([.banner, .sound, .badge])
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                didReceive response: UNNotificationResponse,
                                withCompletionHandler completionHandler: @escaping () -> Void) {
        // Handle notification tap — route to RadarView if match alert
        let userInfo = response.notification.request.content.userInfo
        NotificationCenter.default.post(name: .matchAlertTapped, object: nil, userInfo: userInfo)
        completionHandler()
    }

    // MARK: - Google Sign-In URL Handling

    // NOTE: `OpenURLOptionsKey` is deprecated in iOS 26. Migrating off it requires
    // moving URL handling into a UIWindowSceneDelegate (`scene(_:openURLContexts:)`)
    // or SwiftUI `.onOpenURL`, which is a scene-lifecycle change on the auth-critical
    // Google Sign-In path. Deferred intentionally to avoid an untested regression;
    // the cold-launch case is already covered by `configurationForConnecting` below.
    func application(_ app: UIApplication,
                     open url: URL,
                     options: [UIApplication.OpenURLOptionsKey: Any] = [:]) -> Bool {
        return GIDSignIn.sharedInstance.handle(url)
    }

    // Modern scene-based URL handling
    func application(_ application: UIApplication,
                     configurationForConnecting connectingSceneSession: UISceneSession,
                     options: UIScene.ConnectionOptions) -> UISceneConfiguration {
        let configuration = UISceneConfiguration(name: nil, sessionRole: connectingSceneSession.role)

        // Handle URLs through scene delegate if needed
        if let urlContext = options.urlContexts.first {
            _ = GIDSignIn.sharedInstance.handle(urlContext.url)
        }

        return configuration
    }
}

// MARK: - Notification Names
extension Notification.Name {
    static let matchAlertTapped = Notification.Name("matchAlertTapped")
    static let questModeChanged = Notification.Name("questModeChanged")
    static let proximityUpdated = Notification.Name("proximityUpdated")
}
