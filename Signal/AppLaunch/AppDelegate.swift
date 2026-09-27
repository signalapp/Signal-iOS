//
// Copyright 2026 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import SignalServiceKit
import UIKit

/// Receives app-wide lifecycle events from UIKit, and forwards them to
/// ``AppLifecycleManager``.
///
/// Events tied to the app's UI arrive in ``SceneDelegate`` instead.
@main
final class AppDelegate: UIResponder, UIApplicationDelegate {

    private let lifecycleManager = AppLifecycleManager.shared

    // MARK: - Lifecycle

    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil,
    ) -> Bool {
        return lifecycleManager.didFinishLaunching(launchOptions: launchOptions)
    }

    func applicationDidReceiveMemoryWarning(_ application: UIApplication) {
        lifecycleManager.didReceiveMemoryWarning()
    }

    /// UIKit generally prefers `SceneDelegate.sceneDidDisconnect(_:)` for
    /// scene-based apps, which also calls through to the manager.
    func applicationWillTerminate(_ application: UIApplication) {
        lifecycleManager.willTerminate()
    }

    // MARK: - Orientation

    func application(
        _ application: UIApplication,
        supportedInterfaceOrientationsFor window: UIWindow?,
    ) -> UIInterfaceOrientationMask {
        return lifecycleManager.supportedInterfaceOrientations(for: window)
    }

    // MARK: - Notifications

    func application(_ application: UIApplication, didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data) {
        lifecycleManager.didRegisterForRemoteNotifications(deviceToken: deviceToken)
    }

    func application(_ application: UIApplication, didFailToRegisterForRemoteNotificationsWithError error: Error) {
        lifecycleManager.didFailToRegisterForRemoteNotifications(error: error)
    }

    func application(
        _ application: UIApplication,
        didReceiveRemoteNotification userInfo: [AnyHashable: Any],
        fetchCompletionHandler completionHandler: @escaping (UIBackgroundFetchResult) -> Void,
    ) {
        lifecycleManager.didReceiveRemoteNotification(userInfo, completionHandler: completionHandler)
    }
}
