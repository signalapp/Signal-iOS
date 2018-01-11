//
//  Copyright (c) 2018 Open Whisper Systems. All rights reserved.
//

import UIKit

import SignalMessaging
import PureLayout
import SignalServiceKit
import PromiseKit

@objc
public class ShareViewController: UINavigationController, ShareViewDelegate, SAEFailedViewDelegate {

    enum ShareViewControllerError: Error {
        case assertionError(description: String)
        case unsupportedMedia
        case notRegistered()
    }

    private var hasInitialRootViewController = false
    private var isReadyForAppExtensions = false

    private var progressPoller: ProgressPoller?
    var loadViewController: SAELoadViewController?

    let shareViewNavigationController: UINavigationController = UINavigationController()

    override open func loadView() {
        super.loadView()
        Logger.debug("\(self.logTag) \(#function)")

        // This should be the first thing we do.
        let appContext = ShareAppExtensionContext(rootViewController:self)
        SetCurrentAppContext(appContext)

        DebugLogger.shared().enableTTYLogging()
        if _isDebugAssertConfiguration() {
            DebugLogger.shared().enableFileLogging()
        } else if OWSPreferences.isLoggingEnabled() {
            DebugLogger.shared().enableFileLogging()
        }

        _ = AppVersion()

        startupLogging()

        SetRandFunctionSeed()

        // We don't need to use DeviceSleepManager in the SAE.

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
        guard isReadyForAppExtensions else {
            // If we don't have TSSStorageManager, we can't consult TSAccountManager
            // for isRegistered, so we use OWSPreferences which is usually-accurate
            // copy of that state.
            if OWSPreferences.isRegistered() {
                showNotReadyView()
            } else {
                showNotRegisteredView()
            }
            return
        }

        let loadViewController = SAELoadViewController(delegate: self)
        self.loadViewController = loadViewController

        // Don't display load screen immediately, in hopes that we can avoid it altogether.
        after(seconds: 0.5).then { () -> Void in
            guard self.presentedViewController == nil else {
                Logger.debug("\(self.logTag) setup completed quickly, no need to present load view controller.")
                return
            }

            Logger.debug("\(self.logTag) setup is slow - showing loading screen")
            self.showPrimaryViewController(loadViewController)
        }.retainUntilComplete()

        // We shouldn't set up our environment until after we've consulted isReadyForAppExtensions.
        AppSetup.setupEnvironment({
            return NoopCallMessageHandler()
        }) {
            return NoopNotificationsManager()
        }

        // performUpdateCheck must be invoked after Environment has been initialized because
        // upgrade process may depend on Environment.
        VersionMigrations.performUpdateCheck()

        self.isNavigationBarHidden = true

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

        Logger.info("\(self.logTag) application: didFinishLaunchingWithOptions completed.")

        OWSAnalytics.appLaunchDidBegin()
    }

    deinit {
        Logger.info("\(self.logTag) dealloc")
        NotificationCenter.default.removeObserver(self)
    }

    private func activate() {
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
    func storageIsReady() {
        AssertIsOnMainThread()

        Logger.debug("\(self.logTag) \(#function)")

        if TSAccountManager.isRegistered() {
            Logger.info("\(self.logTag) localNumber: \(TSAccountManager.localNumber)")

            // We don't need to use messageFetcherJob in the SAE.

            // We don't need to use SyncPushTokensJob in the SAE.
        }

        // We don't need to use DeviceSleepManager in the SAE.

        // TODO: Should we distinguish main app and SAE "completion"?
        AppVersion.instance().appLaunchDidComplete()

        Environment.current().contactsManager.loadSignalAccountsFromCache()

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
        AssertIsOnMainThread()

        Logger.debug("\(self.logTag) \(#function)")

        if TSAccountManager.isRegistered() {
            Logger.info("\(self.logTag) localNumber: \(TSAccountManager.localNumber)")

            // We don't need to use ExperienceUpgradeFinder in the SAE.

            // We don't need to use OWSDisappearingMessagesJob in the SAE.

            OWSProfileManager.shared().ensureLocalProfileCached()
        }
    }

    private func ensureRootViewController() {
        Logger.debug("\(self.logTag) \(#function)")

        guard OWSStorage.isStorageReady() else {
            return
        }
        guard !hasInitialRootViewController else {
            return
        }
        hasInitialRootViewController = true

        Logger.info("Presenting initial root view controller")

        if !TSAccountManager.isRegistered() {
            showNotRegisteredView()
        } else if !OWSProfileManager.shared().localProfileExists() {
            // This is a rare edge case, but we want to ensure that the user
            // is has already saved their local profile key in the main app.
            showNotReadyView()
        } else {
            presentConversationPicker()
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
        self.showPrimaryViewController(viewController)
    }

    // MARK: View Lifecycle

    override open func viewDidLoad() {
        super.viewDidLoad()

        Logger.debug("\(self.logTag) \(#function)")

        if isReadyForAppExtensions {
            activate()
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
    }

    @objc
    func owsApplicationWillEnterForeground() throws {
        AssertIsOnMainThread()

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

    public func shareViewWasCompleted() {
        Logger.info("\(self.logTag) \(#function)")

        self.dismiss(animated: true) {
            self.extensionContext!.completeRequest(returningItems: [], completionHandler: nil)
        }
    }

    public func shareViewWasCancelled() {
        Logger.info("\(self.logTag) \(#function)")

        self.dismiss(animated: true) {
            self.extensionContext!.completeRequest(returningItems: [], completionHandler: nil)
        }
    }

    public func shareViewFailed(error: Error) {
        Logger.info("\(self.logTag) \(#function)")

        self.dismiss(animated: true) {
            self.extensionContext!.cancelRequest(withError: error)
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
        shareViewNavigationController.setViewControllers([viewController], animated: false)
        if self.presentedViewController == nil {
            Logger.debug("\(self.logTag) presenting modally: \(viewController)")
            self.present(shareViewNavigationController, animated: true)
        } else {
            Logger.debug("\(self.logTag) modal already presented. swapping modal content for: \(viewController)")
            assert(self.presentedViewController == shareViewNavigationController)
        }
    }

    private func presentConversationPicker() {
        self.buildAttachment().then { attachment -> Void in
            let conversationPicker = SharingThreadPickerViewController(shareViewDelegate: self)
            conversationPicker.attachment = attachment
            self.shareViewNavigationController.isNavigationBarHidden = true
            self.progressPoller = nil
            self.loadViewController = nil
            self.showPrimaryViewController(conversationPicker)
            Logger.info("showing picker with attachment: \(attachment)")
        }.catch { error in
            let alertTitle = NSLocalizedString("SHARE_EXTENSION_UNABLE_TO_BUILD_ATTACHMENT_ALERT_TITLE", comment: "Shown when trying to share content to a Signal user for the share extension. Followed by failure details.")
            OWSAlerts.showAlert(withTitle: alertTitle,
                                message: error.localizedDescription,
                                buttonTitle: CommonStrings.cancelButton) { _ in
                                    self.shareViewWasCancelled()
            }
            owsFail("\(self.logTag) building attachment failed with error: \(error)")
        }.retainUntilComplete()
    }

    private func utiTypeForItem(itemProvider: NSItemProvider) -> String? {
        // Special case URLs.  Many shares (e.g. pdfs) will register kUTTypeURL, but
        // URLs will have kUTTypeURL as their only registered UTI type.
        if itemProvider.registeredTypeIdentifiers.count == 1 {
            if let firstUtiType = itemProvider.registeredTypeIdentifiers.first {
                if firstUtiType == kUTTypeURL as String {
                    return kUTTypeURL as String
                }
            }
        }

        // Order matters if we want to take advantage of share conversion in loadItem,
        // Though currently we just use "data" for most things and rely on our SignalAttachment
        // class to convert types for us.
        let utiTypes: [String] = [kUTTypeImage as String,
                                  kUTTypeData as String]

        let matchingUtiType = utiTypes.first { (utiType: String) -> Bool in
            itemProvider.hasItemConformingToTypeIdentifier(utiType)
        }
        return matchingUtiType
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

        guard let utiType = utiTypeForItem(itemProvider: itemProvider) else {
            let error = ShareViewControllerError.unsupportedMedia
            return Promise(error: error)
        }
        Logger.debug("\(logTag) matched utiType: \(utiType)")

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
        return promise.then { (itemUrl: URL) -> Promise<SignalAttachment> in

            let url: URL = try {
                if self.isVideoNeedingRelocation(itemProvider: itemProvider, itemUrl: itemUrl) {
                    return try SignalAttachment.copyToVideoTempDir(url: itemUrl)
                } else {
                    return itemUrl
                }
            }()

            Logger.debug("\(self.logTag) building DataSource with url: \(url)")

            var rawDataSource: DataSource?
            if utiType == (kUTTypeURL as String) {
                let urlString = url.absoluteString
                rawDataSource = DataSourceValue.dataSource(withOversizeText:urlString)
            } else {
                rawDataSource = DataSourcePath.dataSource(with: url)
            }
            guard let dataSource = rawDataSource else {
                throw ShareViewControllerError.assertionError(description: "Unable to read attachment data")
            }
            if utiType != (kUTTypeURL as String) {
                dataSource.sourceFilename = url.lastPathComponent
            }

            // start with base utiType, but it might be something generic like "image"
            var specificUTIType = utiType
            if utiType == (kUTTypeURL as String) {
                Logger.debug("\(self.logTag) using text UTI type for URL.")
                specificUTIType = kOversizeTextAttachmentUTI as String
            } else if url.pathExtension.count > 0 {
                // Determine a more specific utiType based on file extension
                if let typeExtension = MIMETypeUtil.utiType(forFileExtension: url.pathExtension) {
                    Logger.debug("\(self.logTag) utiType based on extension: \(typeExtension)")
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
                    self.progressPoller = progressPoller
                    progressPoller.startPolling()

                    guard let loadViewController = self.loadViewController else {
                        owsFail("load view controller was unexpectedly nil")
                        return promise
                    }

                    loadViewController.progress = progressPoller.progress
                }

                return promise
            }

            let attachment = SignalAttachment.attachment(dataSource: dataSource, dataUTI: specificUTIType, imageQuality: .medium)
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
        if itemProvider.hasItemConformingToTypeIdentifier(kUTTypeURL as String) {
            return false
        }

        let pathExtension = itemUrl.pathExtension
        guard pathExtension.count > 0 else {
            Logger.verbose("\(self.logTag) in \(#function): item URL has no file extension: \(itemUrl).")
            return false
        }
        guard let utiTypeForURL = MIMETypeUtil.utiType(forFileExtension: pathExtension) else {
            Logger.verbose("\(self.logTag) in \(#function): item has unknown UTI type: \(itemUrl).")
            return false
        }
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
