//
//  SerendipityApp.swift
//  Serendipity
//
//  Created by Henry Greenman on 2/23/26.
//

import SwiftUI
import Combine
import FirebaseCore
import AppTrackingTransparency

@main
struct SerendipityApp: App {
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
        }
    }
}
