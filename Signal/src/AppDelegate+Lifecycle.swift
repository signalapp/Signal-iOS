//
// Copyright 2022 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
import WebRTC
import SignalServiceKit

extension AppDelegate {
    @objc
    func applicationDidBecomeActiveSwift(_ application: UIApplication) {
        AssertIsOnMainThread()

        if didAppLaunchFail {
            Logger.error("App launch failed")
            return
        }

        Logger.warn("applicationDidBecomeActive.")
        if CurrentAppContext().isRunningTests {
            return
        }

        AppReadiness.runNowOrWhenAppDidBecomeReadySync { self.handleActivation() }

        // Clear all notifications whenever we become active.
        // When opening the app from a notification,
        // AppDelegate.didReceiveLocalNotification will always
        // be called _before_ we become active.
        clearAllNotificationsAndRestoreBadgeCount()

        // On every activation, clear old temp directories.
        ClearOldTemporaryDirectories()

        // Ensure that all windows have the correct frame.
        WindowManager.shared.updateWindowFrames()

        Logger.info("applicationDidBecomeActive completed.")
    }

    @objc
    func applicationWillResignActiveSwift(_ application: UIApplication) {
        AssertIsOnMainThread()

        if didAppLaunchFail {
            Logger.error("App launch failed")
            return
        }

        Logger.warn("applicationWillResignActive.")

        clearAllNotificationsAndRestoreBadgeCount()

        Logger.flush()
    }

    @objc
    func applicationDidEnterBackgroundSwift(_ application: UIApplication) {
        Logger.info("applicationDidEnterBackground.")

        Logger.flush()

        if shouldKillAppWhenBackgrounded {
            exit(0)
        }
    }

    @objc
    func applicationWillEnterForegroundSwift(_ application: UIApplication) {
        Logger.info("applicationWillEnterForeground.")
    }

    private static var hasActivated = false

    private func handleActivation() {
        AssertIsOnMainThread()

        let tsRegistrationState: TSRegistrationState = DependenciesBridge.shared.db.read { tx in
            // Always check prekeys after app launches, and sometimes check on app activation.
            let registrationState = DependenciesBridge.shared.tsAccountManager.registrationState(tx: tx)
            if registrationState.isRegistered {
                DependenciesBridge.shared.preKeyManager.checkPreKeysIfNecessary(tx: tx)
            }
            return registrationState
        }

        if !Self.hasActivated {
            Self.hasActivated = true

            RTCInitializeSSL()

            if tsRegistrationState.isRegistered {
                // At this point, potentially lengthy DB locking migrations could be running.
                // Avoid blocking app launch by putting all further possible DB access in async block
                DispatchQueue.global(qos: .default).async {
                    // Clean up any messages that expired since last launch immediately
                    // and continue cleaning in the background.
                    self.disappearingMessagesJob.startIfNecessary()
                }
            } else {
                // Unregistered user should have no unread messages. e.g. if you delete your account.
                AppEnvironment.shared.notificationPresenter.clearAllNotifications()
            }
        }

        // Every time we become active...
        if tsRegistrationState.isRegistered {
            // At this point, potentially lengthy DB locking migrations could be running.
            // Avoid blocking app launch by putting all further possible DB access in async block
            DispatchQueue.main.async {
                AppEnvironment.shared.contactsManagerImpl.fetchSystemContactsOnceIfAlreadyAuthorized()

                // TODO: Should we run this immediately even if we would like to process
                // already decrypted envelopes handed to us by the NSE?
                self.messageFetcherJob.run()

                if !UIApplication.shared.isRegisteredForRemoteNotifications {
                    Logger.info("Retrying to register for remote notifications since user hasn't registered yet.")
                    // Push tokens don't normally change while the app is launched, so checking once during launch is
                    // usually sufficient, but e.g. on iOS11, users who have disabled "Allow Notifications" and disabled
                    // "Background App Refresh" will not be able to obtain an APN token. Enabling those settings does not
                    // restart the app, so we check every activation for users who haven't yet registered.
                    SyncPushTokensJob.run()
                }
            }
        }

        // We want to defer this so that we never call this method until
        // [UIApplicationDelegate applicationDidBecomeActive:] is complete.
        let identityManager = DependenciesBridge.shared.identityManager
        DispatchQueue.main.asyncAfter(deadline: .now() + 1) { identityManager.tryToSyncQueuedVerificationStates() }

        Logger.info("handleActivation completed.")
    }

    private func clearAllNotificationsAndRestoreBadgeCount() {
        AssertIsOnMainThread()

        AppReadiness.runNowOrWhenAppDidBecomeReadySync {
            let oldBadgeValue = UIApplication.shared.applicationIconBadgeNumber
            AppEnvironment.shared.notificationPresenter.clearAllNotifications()
            UIApplication.shared.applicationIconBadgeNumber = oldBadgeValue
        }
    }
}
