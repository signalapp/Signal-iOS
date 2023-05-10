//
// Copyright 2020 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import SignalUI
import UIKit

enum LaunchInterface {
    case registration(RegistrationCoordinatorLoader, RegistrationMode)
    case deprecatedOnboarding(Deprecated_OnboardingController)
    case chatList(Deprecated_OnboardingController)
}

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

    func showLaunchInterface(_ launchInterface: LaunchInterface, launchStartedAt: TimeInterval) {
        AssertIsOnMainThread()
        owsAssert(AppReadiness.isAppReady)

        let startupDuration = CACurrentMediaTime() - launchStartedAt
        Logger.info("Presenting app \(startupDuration) seconds after launch started.")

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(spamChallenge),
            name: SpamChallengeResolver.NeedsCaptchaNotification,
            object: nil
        )

        switch launchInterface {
        case .registration(let registrationLoader, let desiredMode):
            showRegistration(loader: registrationLoader, desiredMode: desiredMode)
            AppReadiness.setUIIsReady()
        case .deprecatedOnboarding(let onboardingController):
            showDeprecatedOnboardingView(onboardingController)
            AppReadiness.setUIIsReady()
        case .chatList(let onboardingController):
            onboardingController.markAsOnboarded()
            showConversationSplitView()
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
        switch desiredMode {
        case .registering:
            Logger.info("Attempting initial registration on app launch")
        case .reRegistering:
            Logger.info("Attempting reregistration on app launch")
        case .changingNumber:
            Logger.info("Attempting change number registration on app launch")
        }
        let coordinator = databaseStorage.write { tx in
            return loader.coordinator(forDesiredMode: desiredMode, transaction: tx.asV2Write)
        }
        let navController = RegistrationNavigationController.withCoordinator(coordinator)

        UIApplication.shared.delegate?.window??.rootViewController = navController

        conversationSplitViewController = nil
    }

    @objc
    private func spamChallenge() {
        SpamCaptchaViewController.presentActionSheet(from: UIApplication.shared.frontmostViewController!)
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
            if SSKEnvironment.hasShared {
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
            title: OWSLocalizedString("DATABASE_INTEGRITY_CHECK_TITLE",
                                     comment: "Title for alert before running a database integrity check"),
            message: OWSLocalizedString("DATABASE_INTEGRITY_CHECK_MESSAGE",
                                       comment: "Message for alert before running a database integrity check"),
            preferredStyle: .alert)
        alert.addAction(.init(title: OWSLocalizedString("DATABASE_INTEGRITY_CHECK_ACTION_RUN",
                                                       comment: "Button to run the database integrity check"),
                              style: .default) { _ in
            let progressView = UIActivityIndicatorView(style: .whiteLarge)
            progressView.color = .gray
            parentVC.view.addSubview(progressView)
            progressView.autoCenterInSuperview()
            progressView.startAnimating()

            var backgroundTask: OWSBackgroundTask? = OWSBackgroundTask(label: "showDatabaseIntegrityCheckUI")

            DispatchQueue.sharedUserInitiated.async {
                GRDBDatabaseStorageAdapter.checkIntegrity()

                owsAssertDebug(backgroundTask != nil)
                backgroundTask = nil

                DispatchQueue.main.async {
                    progressView.removeFromSuperview()
                    completion()
                }
            }
        })
        alert.addAction(.init(title: OWSLocalizedString("DATABASE_INTEGRITY_CHECK_SKIP",
                                                       comment: "Button to skip database integrity check step"),
                              style: .cancel) { _ in
            completion()
        })
        parentVC.present(alert, animated: true)
    }
}
