//
//  Copyright (c) 2017 Open Whisper Systems. All rights reserved.
//

import UIKit

import SignalMessaging
import PureLayout
import SignalServiceKit
import PromiseKit

@objc
public class ShareViewController: UINavigationController, SAELoadViewDelegate, SAEFailedViewDelegate {

    private var contactsSyncing: OWSContactsSyncing?

    private var hasInitialRootViewController = false
    private var isReadyForAppExtensions = false

    override open func loadView() {
        super.loadView()

        Logger.debug("\(self.logTag()) \(#function)")

        // This should be the first thing we do.
        SetCurrentAppContext(ShareAppExtensionContext(rootViewController:self))

        DebugLogger.shared().enableTTYLogging()
        if _isDebugAssertConfiguration() {
            DebugLogger.shared().enableFileLogging()
        } else if (OWSPreferences.isLoggingEnabled()) {
            DebugLogger.shared().enableFileLogging()
        }

        _ = AppVersion()

        startupLogging()

        SetRandFunctionSeed()

        // We don't need to use DeviceSleepManager in the SAE.

        setupEnvironment()

        // TODO:
        //        [UIUtil applySignalAppearence];

        if CurrentAppContext().isRunningTests {
            // TODO: Do we need to implement isRunningTests in the SAE context?
            return
        }

        // If we haven't migrated the database file to the shared data
        // directory we can't load it, and therefore can't init TSSStorageManager,
        // and therefore don't want to setup most of our machinery (Environment,
        // most of the singletons, etc.).  We just want to show an error view and
        // abort.
        isReadyForAppExtensions = OWSPreferences.isReadyForAppExtensions()
        if !isReadyForAppExtensions {
            // If we don't have TSSStorageManager, we can't consult TSAccountManager
            // for isRegistered, so we use OWSPreferences which is usually-accurate
            // copy of that state.
            if (OWSPreferences.isRegistered()) {
                showNotReadyView()
            } else {
                showNotRegisteredView()
            }
            return
        }

        // performUpdateCheck must be invoked after Environment has been initialized because
        // upgrade process may depend on Environment.
        VersionMigrations.performUpdateCheck()

        let loadViewController = SAELoadViewController(delegate:self)
        self.pushViewController(loadViewController, animated: false)
        self.isNavigationBarHidden = false

        // We don't need to use "screen protection" in the SAE.

        contactsSyncing = OWSContactsSyncing(contactsManager:Environment.current().contactsManager,
                                             identityManager:OWSIdentityManager.shared(),
                                             messageSender:Environment.current().messageSender,
                                             profileManager:OWSProfileManager.shared())

        NotificationCenter.default.addObserver(self,
                                               selector: #selector(databaseViewRegistrationComplete),
                                               name: .DatabaseViewRegistrationComplete,
                                               object: nil)
        NotificationCenter.default.addObserver(self,
                                               selector: #selector(registrationStateDidChange),
                                               name: .RegistrationStateDidChange,
                                               object: nil)

        Logger.info("\(self.logTag) application: didFinishLaunchingWithOptions completed.")

        OWSAnalytics.appLaunchDidBegin()
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    private func activate() {
        Logger.debug("\(self.logTag()) \(#function)")

        // We don't need to use "screen protection" in the SAE.

        ensureRootViewController()

        // Always check prekeys after app launches, and sometimes check on app activation.
        TSPreKeyManager.checkPreKeysIfNecessary()

        // We don't need to use RTCInitializeSSL() in the SAE.

        if TSAccountManager.isRegistered() {
            // At this point, potentially lengthy DB locking migrations could be running.
            // Avoid blocking app launch by putting all further possible DB access in async block
            DispatchQueue.global().async { [weak self] in
                guard let strongSelf = self else { return }
                Logger.info("\(strongSelf.logTag) running post launch block for registered user: \(TSAccountManager.localNumber)")

                // We don't need to use OWSDisappearingMessagesJob in the SAE.

                // TODO remove this once we're sure our app boot process is coherent.
                // Currently this happens *before* db registration is complete when
                // launching the app directly, but *after* db registration is complete when
                // the app is launched in the background, e.g. from a voip notification.
                OWSProfileManager.shared().ensureLocalProfileCached()

                // We don't need to use OWSFailedMessagesJob in the SAE.

                // We don't need to use OWSFailedAttachmentDownloadsJob in the SAE.
            }
        } else {
            Logger.info("\(self.logTag) running post launch block for unregistered user.")

            // We don't need to update the app icon badge number in the SAE.

            // We don't need to prod the TSSocketManager in the SAE.
        }

        // TODO: Do we want to move this logic into the notification handler for "SAE will appear".
        if TSAccountManager.isRegistered() {
            DispatchQueue.main.async { [weak self] in
                guard let strongSelf = self else { return }
                Logger.info("\(strongSelf.logTag) running post launch block for registered user: \(TSAccountManager.localNumber)")

                // We don't need to use the TSSocketManager in the SAE.

                Environment.current().contactsManager.fetchSystemContactsOnceIfAlreadyAuthorized()

                // We don't need to fetch messages in the SAE.

                // We don't need to use OWSSyncPushTokensJob in the SAE.
            }
        }
    }

    @objc
    func databaseViewRegistrationComplete() {
        AssertIsOnMainThread()

        Logger.debug("\(self.logTag()) \(#function)")

        if TSAccountManager.isRegistered() {
            Logger.info("\(self.logTag) localNumber: \(TSAccountManager.localNumber)")

            // We don't need to use messageFetcherJob in the SAE.

            // We don't need to use SyncPushTokensJob in the SAE.
        }

        // We don't need to use DeviceSleepManager in the SAE.

        // TODO: Should we distinguish main app and SAE "completion"?
        AppVersion.instance().appLaunchDidComplete()

        ensureRootViewController()

        // We don't need to use OWSMessageReceiver in the SAE.
        // We don't need to use OWSBatchMessageProcessor in the SAE.

        OWSProfileManager.shared().ensureLocalProfileCached()

        // We don't need to use OWSOrphanedDataCleaner in the SAE.

        OWSProfileManager.shared().fetchLocalUsersProfile()

        OWSReadReceiptManager.shared().prepareCachedValues()

        Environment.current().contactsManager.loadLastKnownContactRecipientIds()
    }

    @objc
    func registrationStateDidChange() {
        AssertIsOnMainThread()

        Logger.debug("\(self.logTag()) \(#function)")

        if TSAccountManager.isRegistered() {
            Logger.info("\(self.logTag) localNumber: \(TSAccountManager.localNumber)")

            // We don't need to use ExperienceUpgradeFinder in the SAE.

            // We don't need to use OWSDisappearingMessagesJob in the SAE.

            OWSProfileManager.shared().ensureLocalProfileCached()
        }
    }

    private func ensureRootViewController() {
        Logger.debug("\(self.logTag()) \(#function)")

        guard !TSDatabaseView.hasPendingViewRegistrations() else {
            return
        }
        guard !hasInitialRootViewController else {
            return
        }
        hasInitialRootViewController = true

        Logger.info("Presenting initial root view controller")

        if TSAccountManager.isRegistered() {
            showConversationPicker()
        } else {
            showNotRegisteredView()
        }

        // We don't use the AppUpdateNag in the SAE.
    }

    func startupLogging() {
        Logger.info("iOS Version: \(UIDevice.current.systemVersion)}")

        let locale = NSLocale.current as NSLocale
        if let localeIdentifier = locale.object(forKey:NSLocale.Key.identifier) as? String,
            localeIdentifier.count > 0 {
            Logger.info("Locale Identifier: \(localeIdentifier)")
        } else {
            owsFail("Locale Identifier: Unknown")
        }
        if let countryCode = locale.object(forKey:NSLocale.Key.countryCode) as? String,
            countryCode.count > 0 {
            Logger.info("Country Code: \(countryCode)")
        } else {
            owsFail("Country Code: Unknown")
        }
        if let languageCode = locale.object(forKey:NSLocale.Key.languageCode) as? String,
            languageCode.count > 0 {
            Logger.info("Language Code: \(languageCode)")
        } else {
            owsFail("Language Code: Unknown")
        }
    }

    func setupEnvironment() {
        let environment = Release.releaseEnvironment()
        Environment.setCurrent(environment)

        // Encryption/Decryption mutates session state and must be synchronized on a serial queue.
        SessionCipher.setSessionCipherDispatchQueue(OWSDispatch.sessionStoreQueue())

        let sharedEnv = TextSecureKitEnv(callMessageHandler:SAECallMessageHandler(),
                                         contactsManager:Environment.current().contactsManager,
                                         messageSender:Environment.current().messageSender,
                                         notificationsManager:SAENotificationsManager(),
                                         profileManager:OWSProfileManager.shared())
        TextSecureKitEnv.setShared(sharedEnv)

        TSStorageManager.shared().setupDatabase(safeBlockingMigrations: {
            VersionMigrations.runSafeBlockingMigrations()
        })

        Environment.current().contactsManager.startObserving()
    }

    // MARK: Error Views

    private func showNotReadyView() {
        let failureTitle = NSLocalizedString("SHARE_EXTENSION_NOT_YET_MIGRATED_TITLE",
                                             comment: "Title indicating that the share extension cannot be used until the main app has been launched at least once.")
        let failureMessage = NSLocalizedString("SHARE_EXTENSION_NOT_YET_MIGRATED_MESSAGE",
                                               comment: "Message indicating that the share extension cannot be used until the main app has been launched at least once.")
        showErrorView(title:failureTitle, message:failureMessage)
    }

    private func showNotRegisteredView() {
        let failureTitle = NSLocalizedString("SHARE_EXTENSION_NOT_REGISTERED_TITLE",
                                             comment: "Title indicating that the share extension cannot be used until the user has registered in the main app.")
        let failureMessage = NSLocalizedString("SHARE_EXTENSION_NOT_REGISTERED_MESSAGE",
                                               comment: "Message indicating that the share extension cannot be used until the user has registered in the main app.")
        showErrorView(title:failureTitle, message:failureMessage)
    }

    private func showErrorView(title: String, message: String) {
        let viewController = SAEFailedViewController(delegate:self, title:title, message:message)
        self.setViewControllers([viewController], animated: false)
        self.isNavigationBarHidden = false
    }

    // MARK: View Lifecycle

    override open func viewDidLoad() {
        super.viewDidLoad()

        Logger.debug("\(self.logTag()) \(#function)")

        if isReadyForAppExtensions {
            activate()
        }
    }

    override open func viewWillAppear(_ animated: Bool) {
        Logger.debug("\(self.logTag()) \(#function)")

        super.viewWillAppear(animated)
    }

    override open func viewDidAppear(_ animated: Bool) {
        Logger.debug("\(self.logTag()) \(#function)")

        super.viewDidAppear(animated)
    }

    override open func viewWillDisappear(_ animated: Bool) {
        Logger.debug("\(self.logTag()) \(#function)")

        super.viewWillDisappear(animated)

        Logger.flush()
    }

    override open func viewDidDisappear(_ animated: Bool) {
        Logger.debug("\(self.logTag()) \(#function)")

        super.viewDidDisappear(animated)

        Logger.flush()
    }

    // MARK: SAELoadViewDelegate, SAEFailedViewDelegate

    public func shareExtensionWasCancelled() {
        self.extensionContext!.completeRequest(returningItems: [], completionHandler: nil)
    }

    // MARK: Helpers

    private func showConversationPicker() {
        let conversationPicker = SendExternalFileViewController()
        buildAttachment().then { attachment -> Void in
            conversationPicker.attachment = attachment
            self.setViewControllers([conversationPicker], animated: true)
            Logger.info("showing picker with attachment: \(attachment)")
        }.catch { error in
            let alertTitle = NSLocalizedString("SHARE_EXTENSION_UNABLE_TO_BUILD_ATTACHMENT_ALERT_TITLE", comment: "Shown when trying to share content to a Signal user for the share extension. Followed by failure details.")
            OWSAlerts.showAlert(withTitle: alertTitle,
                                message: error.localizedDescription,
                                buttonTitle: CommonStrings.cancelButton) { _ in
                                    self.shareExtensionWasCancelled()
            }
            owsFail("\(self.logTag) building attachment failed with error: \(error)")
        }.retainUntilComplete()
    }

    enum ShareViewControllerError: Error {
        case assertionError(description: String)
    }

    private func buildAttachment() -> Promise<SignalAttachment> {
        guard let inputItem: NSExtensionItem = self.extensionContext?.inputItems.first as? NSExtensionItem else {
            let error = ShareViewControllerError.assertionError(description: "no input item")
            return Promise(error: error)
        }

        // TODO Multiple attachments. In that case I'm unclear if we'll
        // be given multiple inputItems or a single inputItem with multiple attachments.
        guard let itemProvider: NSItemProvider = inputItem.attachments?.first as? NSItemProvider else {
            let error = ShareViewControllerError.assertionError(description: "No item provider in input item attachments")
            return Promise(error: error)
        }
        Logger.info("\(self.logTag) attachment: \(itemProvider)")

        // TODO support other utiTypes
        let utiType = kUTTypeImage as String

        guard itemProvider.hasItemConformingToTypeIdentifier(utiType) else {
            let error = ShareViewControllerError.assertionError(description: "only supporting images for now")
            return Promise(error: error)
        }

        let (promise, fulfill, reject) = Promise<URL>.pending()

        itemProvider.loadItem(forTypeIdentifier: utiType, options: nil, completionHandler: {
            (provider, error) in

            guard error == nil else {
                reject(error!)
                return
            }

            guard let url = provider as? URL else {
                let unexpectedTypeError = ShareViewControllerError.assertionError(description: "unexpected item type: \(String(describing: provider))")
                reject(unexpectedTypeError)
                return
            }

            fulfill(url)
        })

        // TODO accept other data types
        // TODO whitelist attachment types
        // TODO coerce when necessary and possible
        return promise.then { (url: URL) -> SignalAttachment in
            guard let dataSource = DataSourcePath.dataSource(with: url) else {
                throw ShareViewControllerError.assertionError(description: "Unable to read attachment data")
            }
            dataSource.sourceFilename = url.lastPathComponent

            // start with base utiType, but it might be something generic like "image"
            var specificUTIType = utiType
            if url.pathExtension.count > 0 {
                // Determine a more specific utiType based on file extension
                if let typeExtension = MIMETypeUtil.utiType(forFileExtension: url.pathExtension) {
                    specificUTIType = typeExtension
                }
            }

            let attachment = SignalAttachment.attachment(dataSource: dataSource, dataUTI: specificUTIType)

            return attachment
        }
    }
}
