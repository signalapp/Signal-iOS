//
// Copyright 2020 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import SignalUI
import UIKit

extension SignalApp {
    @objc
    func warmCachesAsync() {
        DispatchQueue.sharedBackground.async {
            InstrumentsMonitor.measure(category: "appstart", parent: "caches", name: "warmEmojiCache") {
                Emoji.warmAvailableCache()
            }
        }
        DispatchQueue.sharedBackground.async {
            InstrumentsMonitor.measure(category: "appstart", parent: "caches", name: "warmWallpaperCaches") {
                Wallpaper.warmCaches()
            }
        }
    }

    @objc
    func dismissAllModals(animated: Bool, completion: (() -> Void)?) {
        guard let window = CurrentAppContext().mainWindow else {
            owsFailDebug("Missing window.")
            return
        }
        guard let rootViewController = window.rootViewController else {
            owsFailDebug("Missing rootViewController.")
            return
        }
        let hasModal = rootViewController.presentedViewController != nil
        if hasModal {
            rootViewController.dismiss(animated: animated, completion: completion)
        } else {
            completion?()
        }
    }

    func ensureRootViewController(
        appDelegate: UIApplicationDelegate,
        launchStartedAt: TimeInterval,
        registrationLoader: RegistrationCoordinatorLoader
    ) {
        AssertIsOnMainThread()

        Logger.info("ensureRootViewController")

        guard AppReadiness.isAppReady, !hasInitialRootViewController else {
            return
        }
        hasInitialRootViewController = true

        let startupDuration = CACurrentMediaTime() - launchStartedAt
        Logger.info("Presenting app \(startupDuration) seconds after launch started.")

        let onboardingController = Deprecated_OnboardingController()

        if FeatureFlags.useNewRegistrationFlow {
            if let lastMode = DependenciesBridge.shared.db.read(block: {
                return registrationLoader.restoreLastMode(transaction: $0)
            }) {
                showRegistration(loader: registrationLoader, desiredMode: lastMode)
                AppReadiness.setUIIsReady()
            // TODO[Registration]: use a db migration to move isComplete state to reg coordinator.
            } else if !onboardingController.isComplete {
                if UIDevice.current.isIPad {
                    showDeprecatedOnboardingView(onboardingController)
                    AppReadiness.setUIIsReady()
                } else {
                    showRegistration(loader: registrationLoader, desiredMode: .registering)
                    AppReadiness.setUIIsReady()
                }
            } else {
                onboardingController.markAsOnboarded()
                showConversationSplitView()
            }
        } else {
            if onboardingController.isComplete {
                onboardingController.markAsOnboarded()
                showConversationSplitView()
            } else {
                showDeprecatedOnboardingView(onboardingController)
            }
        }

        AppUpdateNag.shared.showAppUpgradeNagIfNecessary()

        UIViewController.attemptRotationToDeviceOrientation()
    }

    func showAppSettings(mode: ShowAppSettingsMode) {
        guard let conversationSplitViewController = self.conversationSplitViewControllerForSwift else {
            owsFailDebug("Missing conversationSplitViewController.")
            return
        }
        conversationSplitViewController.showAppSettingsWithMode(mode)
    }

    func showRegistration(loader: RegistrationCoordinatorLoader, desiredMode: RegistrationMode) {
        let coordinator = databaseStorage.write { tx in
            return loader.coordinator(forDesiredMode: desiredMode, transaction: tx.asV2Write)
        }
        let navController = RegistrationNavigationController.withCoordinator(coordinator)

        UIApplication.shared.delegate?.window??.rootViewController = navController

        conversationSplitViewController = nil
    }
}

extension SignalApp {
    @objc(showExportDatabaseUIFromViewController:completion:)
    public static func showExportDatabaseUI(from parentVC: UIViewController, completion: @escaping () -> Void = {}) {
        guard OWSIsTestableBuild() || DebugFlags.internalSettings else {
            // This should NEVER be exposed outside of internal settings.
            // We do not want to expose users to phishing scams. This should only be used for debugging purposes.
            Logger.warn("cannot export database in a public build")
            completion()
            return
        }

        let alert = UIAlertController(
            title: "⚠️⚠️⚠️ Warning!!! ⚠️⚠️⚠️",
            message: "This contains all your contacts, groups, and messages. "
                + "The database file will remain encrypted and the password provided after export, "
                + "but it is still much less secure because it's now out of the app's control.\n\n"
                + "NO ONE AT SIGNAL CAN MAKE YOU DO THIS! Don't do it if you're not comfortable.",
            preferredStyle: .alert)
        alert.addAction(.init(title: "Export", style: .destructive) { _ in
            if SSKEnvironment.hasShared() {
                // Try to sync the database first, since we don't export the WAL.
                _ = try? SSKEnvironment.shared.grdbStorageAdapter.syncTruncatingCheckpoint()
            }
            let databaseFileUrl = GRDBDatabaseStorageAdapter.databaseFileUrl()
            let shareSheet = UIActivityViewController(activityItems: [databaseFileUrl], applicationActivities: nil)
            shareSheet.completionWithItemsHandler = { _, completed, _, error in
                guard completed && error == nil,
                      let password = GRDBDatabaseStorageAdapter.debugOnly_keyData?.hexadecimalString else {
                    completion()
                    return
                }
                UIPasteboard.general.string = password
                let passwordAlert = UIAlertController(title: "Your database password has been copied to the clipboard",
                                                      message: nil,
                                                      preferredStyle: .alert)
                passwordAlert.addAction(.init(title: "OK", style: .default) { _ in
                    completion()
                })
                parentVC.present(passwordAlert, animated: true)
            }
            parentVC.present(shareSheet, animated: true)
        })
        alert.addAction(.init(title: "Cancel", style: .cancel) { _ in
            completion()
        })
        parentVC.present(alert, animated: true)
    }

    @objc(showDatabaseIntegrityCheckUIFromViewController:completion:)
    public static func showDatabaseIntegrityCheckUI(from parentVC: UIViewController,
                                                    completion: @escaping () -> Void = {}) {
        let alert = UIAlertController(
            title: NSLocalizedString("DATABASE_INTEGRITY_CHECK_TITLE",
                                     comment: "Title for alert before running a database integrity check"),
            message: NSLocalizedString("DATABASE_INTEGRITY_CHECK_MESSAGE",
                                       comment: "Message for alert before running a database integrity check"),
            preferredStyle: .alert)
        alert.addAction(.init(title: NSLocalizedString("DATABASE_INTEGRITY_CHECK_ACTION_RUN",
                                                       comment: "Button to run the database integrity check"),
                              style: .default) { _ in
            let progressView = UIActivityIndicatorView(style: .whiteLarge)
            progressView.color = .gray
            parentVC.view.addSubview(progressView)
            progressView.autoCenterInSuperview()
            progressView.startAnimating()

            var backgroundTask: OWSBackgroundTask? = OWSBackgroundTask(label: "showDatabaseIntegrityCheckUI")

            GRDBDatabaseStorageAdapter.logIntegrityChecks().ensure {
                owsAssertDebug(backgroundTask != nil)
                backgroundTask = nil
                progressView.removeFromSuperview()
                completion()
            }.cauterize()
        })
        alert.addAction(.init(title: NSLocalizedString("DATABASE_INTEGRITY_CHECK_SKIP",
                                                       comment: "Button to skip database integrity check step"),
                              style: .cancel) { _ in
            completion()
        })
        parentVC.present(alert, animated: true)
    }
}
