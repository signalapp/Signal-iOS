//
// Copyright 2020 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

public import SignalServiceKit
import SignalUI

enum LaunchInterface {
    case registration(RegistrationCoordinatorLoader, RegistrationMode)
    case secondaryProvisioning
    case chatList
}

public class SignalApp {
    public static let shared = SignalApp()
    private(set) weak var conversationSplitViewController: ConversationSplitViewController?

    private init() {}

    var hasSelectedThread: Bool {
        return conversationSplitViewController?.selectedThread != nil
    }

    func showConversationSplitView(appReadiness: AppReadinessSetter) {
        let splitViewController = ConversationSplitViewController(appReadiness: appReadiness)
        UIApplication.shared.delegate?.window??.rootViewController = splitViewController
        self.conversationSplitViewController = splitViewController
    }

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

    @MainActor
    func showLaunchInterface(_ launchInterface: LaunchInterface, appReadiness: AppReadinessSetter, launchStartedAt: TimeInterval) {
        owsPrecondition(appReadiness.isAppReady)

        let startupDuration = CACurrentMediaTime() - launchStartedAt
        let formattedStartupDuration = String(format: "%.3f", startupDuration)
        Logger.info("Presenting app \(formattedStartupDuration) seconds after launch started.")

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(spamChallenge),
            name: SpamChallengeResolver.NeedsCaptchaNotification,
            object: nil
        )

        switch launchInterface {
        case .registration(let registrationLoader, let desiredMode):
            showRegistration(loader: registrationLoader, desiredMode: desiredMode, appReadiness: appReadiness)
            appReadiness.setUIIsReady()
        case .secondaryProvisioning:
            showSecondaryProvisioning(appReadiness: appReadiness)
            appReadiness.setUIIsReady()
        case .chatList:
            showConversationSplitView(appReadiness: appReadiness)
        }

        AppUpdateNag.shared.showAppUpgradeNagIfNecessary()

        UIViewController.attemptRotationToDeviceOrientation()
    }

    @objc
    private func spamChallenge() {
        let db = DependenciesBridge.shared.db
        let windowManager = AppEnvironment.shared.windowManagerRef

        let frontmostViewController = windowManager.captchaWindow.findFrontmostViewController(ignoringAlerts: true)!
        SpamCaptchaViewController.presentActionSheet(from: frontmostViewController)

        db.write { tx in
            SupportKeyValueStore().setLastChallengeDate(value: Date(), transaction: tx)
        }
    }

    func showRegistration(
        loader: RegistrationCoordinatorLoader,
        desiredMode: RegistrationMode,
        appReadiness: AppReadinessSetter
    ) {
        switch desiredMode {
        case .registering:
            Logger.info("Attempting initial registration on app launch")
        case .reRegistering:
            Logger.info("Attempting reregistration on app launch")
        case .changingNumber:
            Logger.info("Attempting change number registration on app launch")
        }
        let coordinator = SSKEnvironment.shared.databaseStorageRef.write { tx in
            return loader.coordinator(forDesiredMode: desiredMode, transaction: tx)
        }
        let navController = RegistrationNavigationController.withCoordinator(coordinator, appReadiness: appReadiness)

        UIApplication.shared.delegate?.window??.rootViewController = navController

        conversationSplitViewController = nil
    }

    @MainActor
    func showSecondaryProvisioning(appReadiness: AppReadinessSetter) {
        ProvisioningController.presentProvisioningFlow(appReadiness: appReadiness)
        conversationSplitViewController = nil
    }

    // MARK: -

    func showAppSettings(mode: ChatListViewController.ShowAppSettingsMode, completion: (() -> Void)? = nil) {
        guard let conversationSplitViewController else {
            owsFailDebug("Missing conversationSplitViewController.")
            return
        }
        conversationSplitViewController.showAppSettingsWithMode(mode, completion: completion)
    }

    func showCameraCaptureView(completion: ((UINavigationController) -> Void)? = nil) {
        guard let conversationSplitViewController else {
            owsFailDebug("Missing conversationSplitViewController.")
            return
        }
        conversationSplitViewController.showCameraView(completion: completion)
    }

    func showNewConversationView() {
        AssertIsOnMainThread()
        guard let conversationSplitViewController else {
            owsFailDebug("No conversationSplitViewController")
            return
        }
        conversationSplitViewController.showNewConversationView()
    }

    func showMyStories(animated: Bool) {
        AssertIsOnMainThread()

        guard let conversationSplitViewController else {
            owsFailDebug("No conversationSplitViewController")
            return
        }

        Logger.info("")
        conversationSplitViewController.showMyStoriesController(animated: animated)
    }

    // MARK: -

    func presentConversationForAddress(
        _ address: SignalServiceAddress,
        action: ConversationViewAction = .none,
        animated: Bool
    ) {
        let thread = SSKEnvironment.shared.databaseStorageRef.write { transaction in
            return TSContactThread.getOrCreateThread(withContactAddress: address, transaction: transaction)
        }
        presentConversationForThread(
            threadUniqueId: thread.uniqueId,
            action: action,
            animated: animated
        )
    }

    func presentConversationForThread(
        threadUniqueId: String,
        action: ConversationViewAction = .none,
        focusMessageId: String? = nil,
        animated: Bool
    ) {
        AssertIsOnMainThread()

        guard let conversationSplitViewController else {
            owsFailDebug("No conversationSplitViewController")
            return
        }

        Logger.info("")

        DispatchMainThreadSafe {
            if
                focusMessageId == nil,
                let visibleThread = conversationSplitViewController.visibleThread,
                visibleThread.uniqueId == threadUniqueId,
                let conversationViewController = conversationSplitViewController.selectedConversationViewController
            {
                conversationViewController.popKeyBoard()
                if case .updateDraft = action {
                    conversationViewController.reloadDraft()
                }
                return
            }
            conversationSplitViewController.presentThread(
                threadUniqueId: threadUniqueId,
                action: action,
                focusMessageId: focusMessageId,
                animated: animated
            )
        }
    }

    @MainActor
    func presentConversationAndScrollToFirstUnreadMessage(threadUniqueId: String, animated: Bool) {
        guard let conversationSplitViewController else {
            owsFailDebug("No conversationSplitViewController")
            return
        }

        Logger.info("")

        // If there's a presented blocking splash, but the user is trying to open a
        // thread, dismiss it. We'll try again next time they open the app. We
        // don't want to block them from accessing their conversations.
        ExperienceUpgradeManager.dismissSplashWithoutCompletingIfNecessary()

        if let visibleThread = conversationSplitViewController.visibleThread, visibleThread.uniqueId == threadUniqueId {
            AppEnvironment.shared.windowManagerRef.minimizeCallIfNeeded()
            conversationSplitViewController.selectedConversationViewController?.scrollToInitialPosition(animated: animated)
            return
        }

        if let sendMediaNavigationController = conversationSplitViewController.selectedConversationViewController?.presentedViewController as? SendMediaNavigationController {
            if sendMediaNavigationController.hasUnsavedChanges {
                return
            }

            AppEnvironment.shared.windowManagerRef.minimizeCallIfNeeded()
            conversationSplitViewController.presentThread(
                threadUniqueId: threadUniqueId,
                action: .none,
                focusMessageId: nil,
                animated: false
            )
            sendMediaNavigationController.dismiss(animated: animated)
            return
        }

        AppEnvironment.shared.windowManagerRef.minimizeCallIfNeeded()
        conversationSplitViewController.presentThread(
            threadUniqueId: threadUniqueId,
            action: .none,
            focusMessageId: nil,
            animated: animated
        )
    }

    // MARK: -

    func snapshotSplitViewController(afterScreenUpdates: Bool) -> UIView? {
        return conversationSplitViewController?.view?.snapshotView(afterScreenUpdates: afterScreenUpdates)
    }

    // MARK: -

    @MainActor
    func resetLinkedAppDataAndExit(
        localDeviceId: LocalDeviceId,
        keyFetcher: GRDBKeyFetcher,
        registrationStateChangeManager: RegistrationStateChangeManager,
    ) async -> Never {
        // Best effort to unlink ourselves from the server.
        try? await registrationStateChangeManager.unlinkLocalDevice(localDeviceId: localDeviceId, auth: .implicit())
        resetAppDataAndExit(keyFetcher: keyFetcher)
    }

    /// Wipe all app data, and exit the app.
    ///
    /// - Warning
    /// Extremely destructive. Call with great caution.
    ///
    /// - Important
    /// This is used in launch flows, before global singletons are available.
    @MainActor
    func resetAppDataAndExit(keyFetcher: GRDBKeyFetcher) -> Never {
        resetAppData(keyFetcher: keyFetcher)
        exit(0)
    }

    /// Wipe all app data.
    ///
    /// - Warning
    /// Extremely destructive. Call with great caution.
    ///
    /// - Important
    /// This is used in launch flows, before global singletons are available.
    @MainActor
    func resetAppData(keyFetcher: GRDBKeyFetcher) {
        do {
            try keyFetcher.clear()
        } catch {
            owsFailDebug("Could not clear keychain: \(error)")
        }

        func wipeUserDefaults(_ userDefaults: UserDefaults) {
            for (key, _) in userDefaults.dictionaryRepresentation() {
                userDefaults.removeObject(forKey: key)
            }
            userDefaults.synchronize()
        }

        wipeUserDefaults(UserDefaults.standard)
        wipeUserDefaults(CurrentAppContext().appUserDefaults())

        OWSFileSystem.deleteContents(ofDirectory: OWSFileSystem.appSharedDataDirectoryPath())
        OWSFileSystem.deleteContents(ofDirectory: OWSFileSystem.appDocumentDirectoryPath())
        OWSFileSystem.deleteContents(ofDirectory: OWSFileSystem.cachesDirectoryPath())
        OWSFileSystem.deleteContents(ofDirectory: NSTemporaryDirectory())

        UserNotificationPresenter().clearAllNotifications()
        UIApplication.shared.applicationIconBadgeNumber = 0
        AppDelegate.updateApplicationShortcutItems(isRegistered: false)

        DebugLogger.shared.wipeLogsAlways(appContext: CurrentAppContext() as! MainAppContext)
    }

    @MainActor
    func showTransferCompleteAndExit() {
        let actionSheet = ActionSheetController(
            title: OWSLocalizedString(
                "OUTGOING_TRANSFER_COMPLETE_TITLE",
                comment: "Title for action sheet shown when device transfer completes"
            ),
            message: OWSLocalizedString(
                "OUTGOING_TRANSFER_COMPLETE_MESSAGE",
                comment: "Message for action sheet shown when device transfer completes"
            )
        )
        actionSheet.addAction(.init(
            title: OWSLocalizedString(
                "OUTGOING_TRANSFER_COMPLETE_EXIT_ACTION",
                comment: "Button for action sheet shown when device transfer completes; quits the Signal app immediately (does not automatically relaunch, but the user may choose to relaunch)."
            ),
            style: .destructive,
            handler: { _ in
                exit(0)
            }
        ))
        actionSheet.isCancelable = false
        CurrentAppContext().frontmostViewController()?.present(actionSheet, animated: true)
    }

    // MARK: -

    public func showExportDatabaseUI(from parentVC: UIViewController, completion: @escaping () -> Void = {}) {
        guard DebugFlags.internalSettings else {
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
                _ = try? SSKEnvironment.shared.databaseStorageRef.grdbStorage.syncTruncatingCheckpoint()
            }
            let databaseFileUrl = GRDBDatabaseStorageAdapter.databaseFileUrl()
            let shareSheet = UIActivityViewController(activityItems: [databaseFileUrl], applicationActivities: nil)
            shareSheet.completionWithItemsHandler = { _, completed, _, error in
                guard completed, error == nil, let password = SSKEnvironment.shared.databaseStorageRef.keyFetcher.debugOnly_keyData()?.hexadecimalString else {
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

    public func showDatabaseIntegrityCheckUI(
        from parentVC: UIViewController,
        databaseStorage: SDSDatabaseStorage,
        completion: @escaping () -> Void = {}
    ) {
        let alert = UIAlertController(
            title: OWSLocalizedString("DATABASE_INTEGRITY_CHECK_TITLE",
                                     comment: "Title for alert before running a database integrity check"),
            message: OWSLocalizedString("DATABASE_INTEGRITY_CHECK_MESSAGE",
                                       comment: "Message for alert before running a database integrity check"),
            preferredStyle: .alert)
        alert.addAction(.init(title: OWSLocalizedString("DATABASE_INTEGRITY_CHECK_ACTION_RUN",
                                                       comment: "Button to run the database integrity check"),
                              style: .default) { _ in
            let progressView = UIActivityIndicatorView(style: .large)
            progressView.color = .gray
            parentVC.view.addSubview(progressView)
            progressView.autoCenterInSuperview()
            progressView.startAnimating()

            var backgroundTask: OWSBackgroundTask? = OWSBackgroundTask(label: "showDatabaseIntegrityCheckUI")

            DispatchQueue.sharedUserInitiated.async {
                GRDBDatabaseStorageAdapter.checkIntegrity(databaseStorage: databaseStorage)

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
