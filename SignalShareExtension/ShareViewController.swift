//
//  Copyright (c) 2018 Open Whisper Systems. All rights reserved.
//

import UIKit

import SignalMessaging
import PureLayout
import SignalServiceKit
import PromiseKit

@objc
public class ShareViewController: UIViewController, ShareViewDelegate, SAEFailedViewDelegate {

    enum ShareViewControllerError: Error {
        case assertionError(description: String)
        case unsupportedMedia
        case notRegistered()
        case obsoleteShare
    }

    private var hasInitialRootViewController = false
    private var isReadyForAppExtensions = false
    private var areVersionMigrationsComplete = false

    private var progressPoller: ProgressPoller?
    var loadViewController: SAELoadViewController?

    let shareViewNavigationController: OWSNavigationController = OWSNavigationController()

    override open func loadView() {
        super.loadView()

        // This should be the first thing we do.
        let appContext = ShareAppExtensionContext(rootViewController: self)
        SetCurrentAppContext(appContext)

        DebugLogger.shared().enableTTYLogging()
        if _isDebugAssertConfiguration() {
            DebugLogger.shared().enableFileLogging()
        } else if OWSPreferences.isLoggingEnabled() {
            DebugLogger.shared().enableFileLogging()
        }

        Logger.info("\(self.logTag) \(#function)")

        _ = AppVersion()

        startupLogging()

        SetRandFunctionSeed()

        // We don't need to use DeviceSleepManager in the SAE.

        // We don't need to use applySignalAppearence in the SAE.

        if CurrentAppContext().isRunningTests {
            // TODO: Do we need to implement isRunningTests in the SAE context?
            return
        }

        // If we haven't migrated the database file to the shared data
        // directory we can't load it, and therefore can't init TSSPrimaryStorage,
        // and therefore don't want to setup most of our machinery (Environment,
        // most of the singletons, etc.).  We just want to show an error view and
        // abort.
        isReadyForAppExtensions = OWSPreferences.isReadyForAppExtensions()
        guard isReadyForAppExtensions else {
            showNotReadyView()
            return
        }

        let loadViewController = SAELoadViewController(delegate: self)
        self.loadViewController = loadViewController

        // Don't display load screen immediately, in hopes that we can avoid it altogether.
        after(seconds: 0.5).then { [weak self] () -> Void in
            SwiftAssertIsOnMainThread(#function)

            guard let strongSelf = self else { return }
            guard strongSelf.presentedViewController == nil else {
                Logger.debug("\(strongSelf.logTag) setup completed quickly, no need to present load view controller.")
                return
            }

            Logger.debug("\(strongSelf.logTag) setup is slow - showing loading screen")
            strongSelf.showPrimaryViewController(loadViewController)
        }.retainUntilComplete()

        // We shouldn't set up our environment until after we've consulted isReadyForAppExtensions.
        AppSetup.setupEnvironment(callMessageHandlerBlock: {
            return NoopCallMessageHandler()
        },
                                  notificationsProtocolBlock: {
            return NoopNotificationsManager()
        },
                                  migrationCompletion: { [weak self] in
                                    SwiftAssertIsOnMainThread(#function)

                                    guard let strongSelf = self else { return }

                                    // performUpdateCheck must be invoked after Environment has been initialized because
                                    // upgrade process may depend on Environment.
                                    strongSelf.versionMigrationsDidComplete()
        })

        // We don't need to use "screen protection" in the SAE.

        // Ensure OWSContactsSyncing is instantiated.
        OWSContactsSyncing.sharedManager()

        NotificationCenter.default.addObserver(self,
                                               selector: #selector(storageIsReady),
                                               name: .StorageIsReady,
                                               object: nil)
        NotificationCenter.default.addObserver(self,
                                               selector: #selector(registrationStateDidChange),
                                               name: .RegistrationStateDidChange,
                                               object: nil)
        NotificationCenter.default.addObserver(self,
                                               selector: #selector(owsApplicationWillEnterForeground),
                                               name: .OWSApplicationWillEnterForeground,
                                               object: nil)
        NotificationCenter.default.addObserver(self,
                                               selector: #selector(applicationDidEnterBackground),
                                               name: .OWSApplicationDidEnterBackground,
                                               object: nil)

        Logger.info("\(self.logTag) \(#function) completed.")

        OWSAnalytics.appLaunchDidBegin()
    }

    deinit {
        Logger.info("\(self.logTag) deinit")
        NotificationCenter.default.removeObserver(self)

        // Share extensions reside in a process that may be reused between usages.
        // That isn't safe; the codebase is full of statics (e.g. singletons) which
        // we can't easily clean up.
        ExitShareExtension()
    }

    @objc
    public func applicationDidEnterBackground() {
        SwiftAssertIsOnMainThread(#function)

        Logger.info("\(self.logTag) \(#function)")

        if OWSScreenLock.shared.isScreenLockEnabled() {

            Logger.info("\(self.logTag) \(#function) dismissing.")

            self.dismiss(animated: false) { [weak self] in
                SwiftAssertIsOnMainThread(#function)
                guard let strongSelf = self else { return }
                strongSelf.extensionContext!.completeRequest(returningItems: [], completionHandler: nil)
            }
        }
    }

    private func activate() {
        SwiftAssertIsOnMainThread(#function)

        Logger.debug("\(self.logTag) \(#function)")

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

                // We don't need to use OWSFailedMessagesJob in the SAE.

                // We don't need to use OWSFailedAttachmentDownloadsJob in the SAE.
            }
        } else {
            Logger.info("\(self.logTag) running post launch block for unregistered user.")

            // We don't need to update the app icon badge number in the SAE.

            // We don't need to prod the TSSocketManager in the SAE.
        }

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
    func versionMigrationsDidComplete() {
        SwiftAssertIsOnMainThread(#function)

        Logger.debug("\(self.logTag) \(#function)")

        areVersionMigrationsComplete = true

        checkIsAppReady()
    }

    @objc
    func storageIsReady() {
        SwiftAssertIsOnMainThread(#function)

        Logger.debug("\(self.logTag) \(#function)")

        checkIsAppReady()
    }

    @objc
    func checkIsAppReady() {
        SwiftAssertIsOnMainThread(#function)

        // App isn't ready until storage is ready AND all version migrations are complete.
        guard areVersionMigrationsComplete else {
            return
        }
        guard OWSStorage.isStorageReady() else {
            return
        }
        guard !AppReadiness.isAppReady() else {
            // Only mark the app as ready once.
            return
        }

        Logger.debug("\(self.logTag) \(#function)")

        // TODO: Once "app ready" logic is moved into AppSetup, move this line there.
        OWSProfileManager.shared().ensureLocalProfileCached()

        // Note that this does much more than set a flag;
        // it will also run all deferred blocks.
        AppReadiness.setAppIsReady()

        if TSAccountManager.isRegistered() {
            Logger.info("\(self.logTag) localNumber: \(TSAccountManager.localNumber)")

            // We don't need to use messageFetcherJob in the SAE.

            // We don't need to use SyncPushTokensJob in the SAE.
        }

        // We don't need to use DeviceSleepManager in the SAE.

        AppVersion.instance().saeLaunchDidComplete()

        Environment.current().contactsManager.loadSignalAccountsFromCache()
        Environment.current().contactsManager.startObserving()

        ensureRootViewController()

        // We don't need to use OWSMessageReceiver in the SAE.
        // We don't need to use OWSBatchMessageProcessor in the SAE.

        OWSProfileManager.shared().ensureLocalProfileCached()

        // We don't need to use OWSOrphanedDataCleaner in the SAE.

        // We don't need to fetch the local profile in the SAE

        OWSReadReceiptManager.shared().prepareCachedValues()
    }

    @objc
    func registrationStateDidChange() {
        SwiftAssertIsOnMainThread(#function)

        Logger.debug("\(self.logTag) \(#function)")

        if TSAccountManager.isRegistered() {
            Logger.info("\(self.logTag) localNumber: \(TSAccountManager.localNumber)")

            // We don't need to use ExperienceUpgradeFinder in the SAE.

            // We don't need to use OWSDisappearingMessagesJob in the SAE.

            OWSProfileManager.shared().ensureLocalProfileCached()
        }
    }

    private func ensureRootViewController() {
        SwiftAssertIsOnMainThread(#function)

        Logger.debug("\(self.logTag) \(#function)")

        guard AppReadiness.isAppReady() else {
            return
        }
        guard !hasInitialRootViewController else {
            return
        }
        hasInitialRootViewController = true

        Logger.info("\(logTag) Presenting initial root view controller")

        if OWSScreenLock.shared.isScreenLockEnabled() {
            presentScreenLock()
        } else {
            presentContentView()
        }
    }

    private func presentContentView() {
        SwiftAssertIsOnMainThread(#function)

        Logger.debug("\(self.logTag) \(#function)")

        Logger.info("\(logTag) Presenting content view")

        if !TSAccountManager.isRegistered() {
            showNotRegisteredView()
        } else if !OWSProfileManager.shared().localProfileExists() {
            // This is a rare edge case, but we want to ensure that the user
            // is has already saved their local profile key in the main app.
            showNotReadyView()
        } else {
            DispatchQueue.main.async { [weak self] in
                guard let strongSelf = self else { return }
                strongSelf.buildAttachmentAndPresentConversationPicker()
            }
        }

        // We don't use the AppUpdateNag in the SAE.
    }

    func startupLogging() {
        Logger.info("\(self.logTag) iOS Version: \(UIDevice.current.systemVersion)}")

        let locale = NSLocale.current as NSLocale
        if let localeIdentifier = locale.object(forKey: NSLocale.Key.identifier) as? String,
            localeIdentifier.count > 0 {
            Logger.info("\(self.logTag) Locale Identifier: \(localeIdentifier)")
        } else {
            owsFail("Locale Identifier: Unknown")
        }
        if let countryCode = locale.object(forKey: NSLocale.Key.countryCode) as? String,
            countryCode.count > 0 {
            Logger.info("\(self.logTag) Country Code: \(countryCode)")
        } else {
            owsFail("Country Code: Unknown")
        }
        if let languageCode = locale.object(forKey: NSLocale.Key.languageCode) as? String,
            languageCode.count > 0 {
            Logger.info("\(self.logTag) Language Code: \(languageCode)")
        } else {
            owsFail("Language Code: Unknown")
        }
    }

    // MARK: Error Views

    private func showNotReadyView() {
        SwiftAssertIsOnMainThread(#function)

        let failureTitle = NSLocalizedString("SHARE_EXTENSION_NOT_YET_MIGRATED_TITLE",
                                             comment: "Title indicating that the share extension cannot be used until the main app has been launched at least once.")
        let failureMessage = NSLocalizedString("SHARE_EXTENSION_NOT_YET_MIGRATED_MESSAGE",
                                               comment: "Message indicating that the share extension cannot be used until the main app has been launched at least once.")
        showErrorView(title: failureTitle, message: failureMessage)
    }

    private func showNotRegisteredView() {
        SwiftAssertIsOnMainThread(#function)

        let failureTitle = NSLocalizedString("SHARE_EXTENSION_NOT_REGISTERED_TITLE",
                                             comment: "Title indicating that the share extension cannot be used until the user has registered in the main app.")
        let failureMessage = NSLocalizedString("SHARE_EXTENSION_NOT_REGISTERED_MESSAGE",
                                               comment: "Message indicating that the share extension cannot be used until the user has registered in the main app.")
        showErrorView(title: failureTitle, message: failureMessage)
    }

    private func showErrorView(title: String, message: String) {
        SwiftAssertIsOnMainThread(#function)

        let viewController = SAEFailedViewController(delegate: self, title: title, message: message)
        self.showPrimaryViewController(viewController)
    }

    // MARK: View Lifecycle

    override open func viewDidLoad() {
        super.viewDidLoad()

        Logger.debug("\(self.logTag) \(#function)")

        if isReadyForAppExtensions {
            AppReadiness.runNowOrWhenAppIsReady { [weak self] in
                SwiftAssertIsOnMainThread(#function)
                guard let strongSelf = self else { return }
                strongSelf.activate()
            }
        }
    }

    override open func viewWillAppear(_ animated: Bool) {
        Logger.debug("\(self.logTag) \(#function)")

        super.viewWillAppear(animated)
    }

    override open func viewDidAppear(_ animated: Bool) {
        Logger.debug("\(self.logTag) \(#function)")

        super.viewDidAppear(animated)
    }

    override open func viewWillDisappear(_ animated: Bool) {
        Logger.debug("\(self.logTag) \(#function)")

        super.viewWillDisappear(animated)

        Logger.flush()
    }

    override open func viewDidDisappear(_ animated: Bool) {
        Logger.debug("\(self.logTag) \(#function)")

        super.viewDidDisappear(animated)

        Logger.flush()

        // Share extensions reside in a process that may be reused between usages.
        // That isn't safe; the codebase is full of statics (e.g. singletons) which
        // we can't easily clean up.
        ExitShareExtension()
    }

    @objc
    func owsApplicationWillEnterForeground() throws {
        SwiftAssertIsOnMainThread(#function)

        Logger.debug("\(self.logTag) \(#function)")

        // If a user unregisters in the main app, the SAE should shut down
        // immediately.
        guard !TSAccountManager.isRegistered() else {
            // If user is registered, do nothing.
            return
        }
        guard let firstViewController = shareViewNavigationController.viewControllers.first else {
            // If no view has been presented yet, do nothing.
            return
        }
        if let _ = firstViewController as? SAEFailedViewController {
            // If root view is an error view, do nothing.
            return
        }
        throw ShareViewControllerError.notRegistered()
    }

    // MARK: ShareViewDelegate, SAEFailedViewDelegate

    public func shareViewWasUnlocked() {
        Logger.info("\(self.logTag) \(#function)")

        presentContentView()
    }

    public func shareViewWasCompleted() {
        Logger.info("\(self.logTag) \(#function)")

        self.dismiss(animated: true) { [weak self] in
            SwiftAssertIsOnMainThread(#function)
            guard let strongSelf = self else { return }
            strongSelf.extensionContext!.completeRequest(returningItems: [], completionHandler: nil)
        }
    }

    public func shareViewWasCancelled() {
        Logger.info("\(self.logTag) \(#function)")

        self.dismiss(animated: true) { [weak self] in
            SwiftAssertIsOnMainThread(#function)
            guard let strongSelf = self else { return }
            strongSelf.extensionContext!.completeRequest(returningItems: [], completionHandler: nil)
        }
    }

    public func shareViewFailed(error: Error) {
        Logger.info("\(self.logTag) \(#function)")

        self.dismiss(animated: true) { [weak self] in
            SwiftAssertIsOnMainThread(#function)
            guard let strongSelf = self else { return }
            strongSelf.extensionContext!.cancelRequest(withError: error)
        }
    }

    // MARK: Helpers

    // This view controller is not visible to the user. It exists to intercept touches, set up the
    // extensions dependencies, and eventually present a visible view to the user.
    // For speed of presentation, we only present a single modal, and if it's already been presented
    // we swap out the contents.
    // e.g. if loading is taking a while, the user will see the load screen presented with a modal
    // animation. Next, when loading completes, the load view will be switched out for the contact
    // picker view.
    private func showPrimaryViewController(_ viewController: UIViewController) {
        SwiftAssertIsOnMainThread(#function)

        shareViewNavigationController.setViewControllers([viewController], animated: false)
        if self.presentedViewController == nil {
            Logger.debug("\(self.logTag) presenting modally: \(viewController)")
            self.present(shareViewNavigationController, animated: true)
        } else {
            Logger.debug("\(self.logTag) modal already presented. swapping modal content for: \(viewController)")
            assert(self.presentedViewController == shareViewNavigationController)
        }
    }

    private func buildAttachmentAndPresentConversationPicker() {
        SwiftAssertIsOnMainThread(#function)

        self.buildAttachment().then { [weak self] attachment -> Void in
            SwiftAssertIsOnMainThread(#function)
            guard let strongSelf = self else { return }

            strongSelf.progressPoller = nil
            strongSelf.loadViewController = nil

            let conversationPicker = SharingThreadPickerViewController(shareViewDelegate: strongSelf)
            Logger.debug("\(strongSelf.logTag) presentConversationPicker: \(conversationPicker)")
            conversationPicker.attachment = attachment
            strongSelf.showPrimaryViewController(conversationPicker)
            Logger.info("\(strongSelf.logTag) showing picker with attachment: \(attachment)")
        }.catch {[weak self]  error in
            SwiftAssertIsOnMainThread(#function)
            guard let strongSelf = self else { return }

            let alertTitle = NSLocalizedString("SHARE_EXTENSION_UNABLE_TO_BUILD_ATTACHMENT_ALERT_TITLE",
                                               comment: "Shown when trying to share content to a Signal user for the share extension. Followed by failure details.")
            OWSAlerts.showAlert(title: alertTitle,
                                message: error.localizedDescription,
                                buttonTitle: CommonStrings.cancelButton) { _ in
                                    strongSelf.shareViewWasCancelled()
            }
            owsFail("\(strongSelf.logTag) building attachment failed with error: \(error)")
        }.retainUntilComplete()
    }

    private func presentScreenLock() {
        SwiftAssertIsOnMainThread(#function)

        let screenLockUI = SAEScreenLockViewController(shareViewDelegate: self)
        Logger.debug("\(self.logTag) presentScreenLock: \(screenLockUI)")
        showPrimaryViewController(screenLockUI)
        Logger.info("\(self.logTag) showing screen lock")
    }

    private class func itemMatchesSpecificUtiType(itemProvider: NSItemProvider, utiType: String) -> Bool {
        // URLs, contacts and other special items have to be detected separately.
        // Many shares (e.g. pdfs) will register many UTI types and/or conform to kUTTypeData.
        guard itemProvider.registeredTypeIdentifiers.count == 1 else {
            return false
        }
        guard let firstUtiType = itemProvider.registeredTypeIdentifiers.first else {
            return false
        }
        return firstUtiType == utiType
    }

    private class func isUrlItem(itemProvider: NSItemProvider) -> Bool {
        return itemMatchesSpecificUtiType(itemProvider: itemProvider,
                                          utiType: kUTTypeURL as String)
    }

    private class func isContactItem(itemProvider: NSItemProvider) -> Bool {
        return itemMatchesSpecificUtiType(itemProvider: itemProvider,
                                          utiType: kUTTypeContact as String)
    }

    private class func utiType(itemProvider: NSItemProvider) -> String? {
        Logger.info("\(self.logTag) utiTypeForItem: \(itemProvider.registeredTypeIdentifiers)")

        if isUrlItem(itemProvider: itemProvider) {
            return kUTTypeURL as String
        } else if isContactItem(itemProvider: itemProvider) {
            return kUTTypeContact as String
        }

        // Use the first UTI that conforms to "data".
        let matchingUtiType = itemProvider.registeredTypeIdentifiers.first { (utiType: String) -> Bool in
            UTTypeConformsTo(utiType as CFString, kUTTypeData)
        }
        return matchingUtiType
    }

    private class func preferredItemProvider(inputItem: NSExtensionItem) -> NSItemProvider? {
        guard let attachments = inputItem.attachments else {
            return nil
        }

        // Prefer a URL provider if available
        if let preferredAttachment = attachments.first(where: { (attachment: Any) -> Bool in
            guard let itemProvider = attachment as? NSItemProvider else {
                return false
            }
            return isUrlItem(itemProvider: itemProvider)
        }) {
                return preferredAttachment as? NSItemProvider
        }

        // else return whatever is available
        return inputItem.attachments?.first as? NSItemProvider
    }

    private class func createDataSource(utiType: String, url: URL, customFileName: String?) -> DataSource? {
        if utiType == (kUTTypeURL as String) {
            // Share URLs as oversize text messages whose text content is the URL.
            //
            // NOTE: SharingThreadPickerViewController will try to unpack them
            //       and send them as normal text messages if possible.
            let urlString = url.absoluteString
            return DataSourceValue.dataSource(withOversizeText: urlString)
        } else if UTTypeConformsTo(utiType as CFString, kUTTypeText) {
            // Share text as oversize text messages.
            //
            // NOTE: SharingThreadPickerViewController will try to unpack them
            //       and send them as normal text messages if possible.
            return DataSourcePath.dataSource(with: url)
        } else {
            guard let dataSource = DataSourcePath.dataSource(with: url) else {
                return nil
            }

            if let customFileName = customFileName {
                dataSource.sourceFilename = customFileName
            } else {
                // Ignore the filename for URLs.
                dataSource.sourceFilename = url.lastPathComponent
            }
            return dataSource
        }
    }

    private func buildAttachment() -> Promise<SignalAttachment> {
        guard let inputItem: NSExtensionItem = self.extensionContext?.inputItems.first as? NSExtensionItem else {
            let error = ShareViewControllerError.assertionError(description: "no input item")
            return Promise(error: error)
        }

        // A single inputItem can have multiple attachments, e.g. sharing from Firefox gives
        // one url attachment and another text attachment, where the the url would be https://some-news.com/articles/123-cat-stuck-in-tree
        // and the text attachment would be something like "Breaking news - cat stuck in tree"
        //
        // FIXME: For now, we prefer the URL provider and discard the text provider, since it's more useful to share the URL than the caption
        // but we *should* include both. This will be a bigger change though since our share extension is currently heavily predicated
        // on one itemProvider per share.
        guard let itemProvider: NSItemProvider = type(of: self).preferredItemProvider(inputItem: inputItem) else {
            let error = ShareViewControllerError.assertionError(description: "No item provider in input item attachments")
            return Promise(error: error)
        }
        Logger.info("\(self.logTag) attachment: \(itemProvider)")

        // We need to be very careful about which UTI type we use.
        //
        // * In the case of "textual" shares (e.g. web URLs and text snippets), we want to
        //   coerce the UTI type to kUTTypeURL or kUTTypeText.
        // * We want to treat shared files as file attachments.  Therefore we do not
        //   want to treat file URLs like web URLs.
        // * UTIs aren't very descriptive (there are far more MIME types than UTI types)
        //   so in the case of file attachments we try to refine the attachment type
        //   using the file extension.
        guard let srcUtiType = ShareViewController.utiType(itemProvider: itemProvider) else {
            let error = ShareViewControllerError.unsupportedMedia
            return Promise(error: error)
        }
        Logger.debug("\(logTag) matched utiType: \(srcUtiType)")

        let (promise, fulfill, reject) = Promise<(itemUrl: URL, utiType: String)>.pending()

        var customFileName: String?
        var isConvertibleToTextMessage = false
        var isConvertibleToContactShare = false

        let loadCompletion: NSItemProvider.CompletionHandler = { [weak self]
            (value, error) in

            guard let strongSelf = self else { return }

            guard error == nil else {
                reject(error!)
                return
            }

            guard let value = value else {
                let missingProviderError = ShareViewControllerError.assertionError(description: "missing item provider")
                reject(missingProviderError)
                return
            }

            Logger.info("\(strongSelf.logTag) value type: \(type(of: value))")

            if let data = value as? Data {
                // Although we don't support contacts _yet_, when we do we'll want to make
                // sure they are shared with a reasonable filename.
                if ShareViewController.itemMatchesSpecificUtiType(itemProvider: itemProvider,
                                                                  utiType: kUTTypeVCard as String) {
                    customFileName = "Contact.vcf"

                    if Contact(vCardData: data) != nil {
                        isConvertibleToContactShare = true
                    } else {
                        Logger.error("\(strongSelf.logTag) could not parse vcard.")
                        let writeError = ShareViewControllerError.assertionError(description: "Could not parse vcard data.")
                        reject(writeError)
                        return
                    }
                }

                let customFileExtension = MIMETypeUtil.fileExtension(forUTIType: srcUtiType)
                guard let tempFilePath = OWSFileSystem.writeData(toTemporaryFile: data, fileExtension: customFileExtension) else {
                    let writeError = ShareViewControllerError.assertionError(description: "Error writing item data: \(String(describing: error))")
                    reject(writeError)
                    return
                }
                let fileUrl = URL(fileURLWithPath: tempFilePath)
                fulfill((itemUrl: fileUrl, utiType: srcUtiType))
            } else if let string = value as? String {
                Logger.debug("\(strongSelf.logTag) string provider: \(string)")
                guard let data = string.filterStringForDisplay().data(using: String.Encoding.utf8) else {
                    let writeError = ShareViewControllerError.assertionError(description: "Error writing item data: \(String(describing: error))")
                    reject(writeError)
                    return
                }
                guard let tempFilePath = OWSFileSystem.writeData(toTemporaryFile: data, fileExtension: "txt") else {
                    let writeError = ShareViewControllerError.assertionError(description: "Error writing item data: \(String(describing: error))")
                    reject(writeError)
                    return
                }

                let fileUrl = URL(fileURLWithPath: tempFilePath)

                isConvertibleToTextMessage = !itemProvider.registeredTypeIdentifiers.contains(kUTTypeFileURL as String)

                if UTTypeConformsTo(srcUtiType as CFString, kUTTypeText) {
                    fulfill((itemUrl: fileUrl, utiType: srcUtiType))
                } else {
                    fulfill((itemUrl: fileUrl, utiType:  kUTTypeText as String))
                }
            } else if let url = value as? URL {
                // If the share itself is a URL (e.g. a link from Safari), try to send this as a text message.
                isConvertibleToTextMessage = (itemProvider.registeredTypeIdentifiers.contains(kUTTypeURL as String) &&
                    !itemProvider.registeredTypeIdentifiers.contains(kUTTypeFileURL as String))
                if isConvertibleToTextMessage {
                    fulfill((itemUrl: url, utiType: kUTTypeURL as String))
                } else {
                    fulfill((itemUrl: url, utiType: srcUtiType))
                }
            } else if let image = value as? UIImage {
                if let data = UIImagePNGRepresentation(image) {
                    let tempFilePath = OWSFileSystem.temporaryFilePath(withFileExtension: "png")
                    do {
                        let url = NSURL.fileURL(withPath: tempFilePath)
                        try data.write(to: url)
                        fulfill((url, srcUtiType))
                    } catch {
                        reject(ShareViewControllerError.assertionError(description: "couldn't write UIImage: \(String(describing: error))"))
                    }
                } else {
                    reject(ShareViewControllerError.assertionError(description: "couldn't convert UIImage to PNG: \(String(describing: error))"))
                }
            } else {
                // It's unavoidable that we may sometimes receives data types that we
                // don't know how to handle.
                let unexpectedTypeError = ShareViewControllerError.assertionError(description: "unexpected value: \(String(describing: value))")
                reject(unexpectedTypeError)
            }
        }

        itemProvider.loadItem(forTypeIdentifier: srcUtiType, options: nil, completionHandler: loadCompletion)

        return promise.then { [weak self] (itemUrl: URL, utiType: String) -> Promise<SignalAttachment> in
            guard let strongSelf = self else {
                let error = ShareViewControllerError.obsoleteShare
                return Promise(error: error)
            }

            let url: URL = try {
                if strongSelf.isVideoNeedingRelocation(itemProvider: itemProvider, itemUrl: itemUrl) {
                    return try SignalAttachment.copyToVideoTempDir(url: itemUrl)
                } else {
                    return itemUrl
                }
            }()

            Logger.debug("\(strongSelf.logTag) building DataSource with url: \(url), utiType: \(utiType)")

            guard let dataSource = ShareViewController.createDataSource(utiType: utiType, url: url, customFileName: customFileName) else {
                throw ShareViewControllerError.assertionError(description: "Unable to read attachment data")
            }

            // start with base utiType, but it might be something generic like "image"
            var specificUTIType = utiType
            if utiType == (kUTTypeURL as String) {
                // Use kUTTypeURL for URLs.
            } else if UTTypeConformsTo(utiType as CFString, kUTTypeText) {
                // Use kUTTypeText for text.
            } else if url.pathExtension.count > 0 {
                // Determine a more specific utiType based on file extension
                if let typeExtension = MIMETypeUtil.utiType(forFileExtension: url.pathExtension) {
                    Logger.debug("\(strongSelf.logTag) utiType based on extension: \(typeExtension)")
                    specificUTIType = typeExtension
                }
            }

            guard !SignalAttachment.isInvalidVideo(dataSource: dataSource, dataUTI: specificUTIType) else {
                // This can happen, e.g. when sharing a quicktime-video from iCloud drive.

                let (promise, exportSession) = SignalAttachment.compressVideoAsMp4(dataSource: dataSource, dataUTI: specificUTIType)

                // TODO: How can we move waiting for this export to the end of the share flow rather than having to do it up front?
                // Ideally we'd be able to start it here, and not block the UI on conversion unless there's still work to be done
                // when the user hits "send".
                if let exportSession = exportSession {
                    let progressPoller = ProgressPoller(timeInterval: 0.1, ratioCompleteBlock: { return exportSession.progress })
                    strongSelf.progressPoller = progressPoller
                    progressPoller.startPolling()

                    guard let loadViewController = strongSelf.loadViewController else {
                        owsFail("load view controller was unexpectedly nil")
                        return promise
                    }

                    DispatchQueue.main.async {
                        loadViewController.progress = progressPoller.progress
                    }
                }

                return promise
            }

            let attachment = SignalAttachment.attachment(dataSource: dataSource, dataUTI: specificUTIType, imageQuality: .medium)
            if isConvertibleToContactShare {
                Logger.info("\(strongSelf.logTag) isConvertibleToContactShare")
                attachment.isConvertibleToContactShare = isConvertibleToContactShare
            } else if isConvertibleToTextMessage {
                Logger.info("\(strongSelf.logTag) isConvertibleToTextMessage")
                attachment.isConvertibleToTextMessage = isConvertibleToTextMessage
            }
            return Promise(value: attachment)
        }
    }

    // Some host apps (e.g. iOS Photos.app) sometimes auto-converts some video formats (e.g. com.apple.quicktime-movie)
    // into mp4s as part of the NSItemProvider `loadItem` API. (Some files the Photo's app doesn't auto-convert)
    //
    // However, when using this url to the converted item, AVFoundation operations such as generating a
    // preview image and playing the url in the AVMoviePlayer fails with an unhelpful error: "The operation could not be completed"
    //
    // We can work around this by first copying the media into our container.
    //
    // I don't understand why this is, and I haven't found any relevant documentation in the NSItemProvider
    // or AVFoundation docs.
    //
    // Notes:
    //
    // These operations succeed when sending a video which initially existed on disk as an mp4.
    // (e.g. Alice sends a video to Bob through the main app, which ensures it's an mp4. Bob saves it, then re-shares it)
    //
    // I *did* verify that the size and SHA256 sum of the original url matches that of the copied url. So there
    // is no difference between the contents of the file, yet one works one doesn't.
    // Perhaps the AVFoundation APIs require some extra file system permssion we don't have in the
    // passed through URL.
    private func isVideoNeedingRelocation(itemProvider: NSItemProvider, itemUrl: URL) -> Bool {
        let pathExtension = itemUrl.pathExtension
        guard pathExtension.count > 0 else {
            Logger.verbose("\(self.logTag) in \(#function): item URL has no file extension: \(itemUrl).")
            return false
        }
        guard let utiTypeForURL = MIMETypeUtil.utiType(forFileExtension: pathExtension) else {
            Logger.verbose("\(self.logTag) in \(#function): item has unknown UTI type: \(itemUrl).")
            return false
        }
        Logger.verbose("\(self.logTag) utiTypeForURL: \(utiTypeForURL)")
        guard utiTypeForURL == kUTTypeMPEG4 as String else {
            // Either it's not a video or it was a video which was not auto-converted to mp4.
            // Not affected by the issue.
            return false
        }

        // If video file already existed on disk as an mp4, then the host app didn't need to
        // apply any conversion, so no need to relocate the app.
        return !itemProvider.registeredTypeIdentifiers.contains(kUTTypeMPEG4 as String)
    }
}

// Exposes a Progress object, whose progress is updated by polling the return of a given block
private class ProgressPoller {

    let TAG = "[ProgressPoller]"

    let progress: Progress
    private(set) var timer: Timer?

    // Higher number offers higher ganularity
    let progressTotalUnitCount: Int64 = 10000
    private let timeInterval: Double
    private let ratioCompleteBlock: () -> Float

    init(timeInterval: TimeInterval, ratioCompleteBlock: @escaping () -> Float) {
        self.timeInterval = timeInterval
        self.ratioCompleteBlock = ratioCompleteBlock

        self.progress = Progress()

        progress.totalUnitCount = progressTotalUnitCount
        progress.completedUnitCount = Int64(ratioCompleteBlock() * Float(progressTotalUnitCount))
    }

    func startPolling() {
        guard self.timer == nil else {
            owsFail("already started timer")
            return
        }

        self.timer = WeakTimer.scheduledTimer(timeInterval: timeInterval, target: self, userInfo: nil, repeats: true) { [weak self] (timer) in
            guard let strongSelf = self else {
                return
            }

            let completedUnitCount = Int64(strongSelf.ratioCompleteBlock() * Float(strongSelf.progressTotalUnitCount))
            strongSelf.progress.completedUnitCount = completedUnitCount

            if completedUnitCount == strongSelf.progressTotalUnitCount {
                Logger.debug("\(strongSelf.TAG) progress complete")
                timer.invalidate()
            }
        }
    }
}
