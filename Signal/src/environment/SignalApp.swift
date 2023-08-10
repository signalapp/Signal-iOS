//
// Copyright 2020 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import SignalMessaging
import SignalServiceKit
import SignalUI

enum LaunchInterface {
    case registration(RegistrationCoordinatorLoader, RegistrationMode)
    case secondaryProvisioning
    case chatList
}

@objc
public class SignalApp: NSObject {

    @objc
    public static let shared = SignalApp()

    private(set) weak var conversationSplitViewController: ConversationSplitViewController?

    private override init() {
        super.init()

        AppReadiness.runNowOrWhenUIDidBecomeReadySync {
            self.warmCachesAsync()
        }
    }

    private func warmCachesAsync() {
        DispatchQueue.sharedBackground.async {
            InstrumentsMonitor.measure(category: "appstart", parent: "caches", name: "warmEmojiCache") {
                Emoji.warmAvailableCache()
            }
        }
    }
}

extension SignalApp {

    var hasSelectedThread: Bool {
        return conversationSplitViewController?.selectedThread != nil
    }

    func showConversationSplitView() {
        let splitViewController = ConversationSplitViewController()
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
        case .secondaryProvisioning:
            showSecondaryProvisioning()
            AppReadiness.setUIIsReady()
        case .chatList:
            showConversationSplitView()
        }

        AppUpdateNag.shared.showAppUpgradeNagIfNecessary()

        UIViewController.attemptRotationToDeviceOrientation()
    }

    func showAppSettings(mode: ChatListViewController.ShowAppSettingsMode) {
        guard let conversationSplitViewController else {
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

    @objc
    func showNewConversationView() {
        AssertIsOnMainThread()
        guard let conversationSplitViewController else {
            owsFailDebug("No conversationSplitViewController")
            return
        }
        conversationSplitViewController.showNewConversationView()
    }

    func presentConversationForAddress(
        _ address: SignalServiceAddress,
        action: ConversationViewAction = .none,
        animated: Bool
    ) {
        let thread = databaseStorage.write { transaction in
            return TSContactThread.getOrCreateThread(withContactAddress: address, transaction: transaction)
        }
        presentConversationForThread(thread, action: action, animated: animated)
    }

    func presentConversationForThread(
        _ thread: TSThread,
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
            if let visibleThread = conversationSplitViewController.visibleThread,
               visibleThread.uniqueId == thread.uniqueId,
               let conversationViewController = conversationSplitViewController.selectedConversationViewController {
                conversationViewController.popKeyBoard()
                if case .updateDraft = action {
                    conversationViewController.reloadDraft()
                }
                return
            }
            conversationSplitViewController.presentThread(thread, action: action, focusMessageId: focusMessageId, animated: animated)
        }
    }

    @objc
    func presentConversationAndScrollToFirstUnreadMessage(forThreadId threadId: String, animated: Bool) {
        AssertIsOnMainThread()
        owsAssertDebug(!threadId.isEmpty)

        guard let conversationSplitViewController else {
            owsFailDebug("No conversationSplitViewController")
            return
        }

        Logger.info("")

        guard let thread = databaseStorage.read(block: { transaction in
            return TSThread.anyFetch(uniqueId: threadId, transaction: transaction)
        }) else {
            owsFailDebug("unable to find thread with id: \(threadId)")
            return
        }

        DispatchMainThreadSafe {
            // If there's a presented blocking splash, but the user is trying to open a thread,
            // dismiss it. We'll try again next time they open the app. We don't want to block
            // them from accessing their conversations.
            ExperienceUpgradeManager.dismissSplashWithoutCompletingIfNecessary()

            if let visibleThread = conversationSplitViewController.visibleThread, visibleThread.uniqueId == thread.uniqueId {
                conversationSplitViewController.selectedConversationViewController?.scrollToInitialPosition(animated: animated)
                return
            }

            conversationSplitViewController.presentThread(thread, action: .none, focusMessageId: nil, animated: animated)
        }
    }

    func snapshotSplitViewController(afterScreenUpdates: Bool) -> UIView? {
        return conversationSplitViewController?.view?.snapshotView(afterScreenUpdates: afterScreenUpdates)
    }
}

extension SignalApp {

    static func resetAppDataWithUI() {
        Logger.info("")

        DispatchMainThreadSafe {
            guard let fromVC = UIApplication.shared.frontmostViewController else { return }
            ModalActivityIndicatorViewController.present(
                fromViewController: fromVC,
                canCancel: true,
                backgroundBlock: { _ in
                    SignalApp.resetAppData()
                }
            )
        }
    }

    static func resetAppData() {
        // This _should_ be wiped out below.
        Logger.info("")
        Logger.flush()

        DispatchSyncMainThreadSafe {
            databaseStorage.resetAllStorage()
            OWSUserProfile.resetProfileStorage()
            preferences.removeAllValues()
            AppEnvironment.shared.notificationPresenter.clearAllNotifications()
            OWSFileSystem.deleteContents(ofDirectory: OWSFileSystem.appSharedDataDirectoryPath())
            OWSFileSystem.deleteContents(ofDirectory: OWSFileSystem.appDocumentDirectoryPath())
            OWSFileSystem.deleteContents(ofDirectory: OWSFileSystem.cachesDirectoryPath())
            OWSFileSystem.deleteContents(ofDirectory: OWSTemporaryDirectory())
            OWSFileSystem.deleteContents(ofDirectory: NSTemporaryDirectory())
            AppDelegate.updateApplicationShortcutItems(isRegisteredAndReady: false)
        }

        DebugLogger.shared().wipeLogsAlways(appContext: CurrentAppContext() as! MainAppContext)
        exit(0)
    }
}

extension SignalApp {

    func showSecondaryProvisioning() {
        ProvisioningController.presentProvisioningFlow()
        conversationSplitViewController = nil
    }
}

extension SignalApp {

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
            let progressView = UIActivityIndicatorView(style: .large)
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
