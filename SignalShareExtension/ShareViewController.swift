//
//  Copyright (c) 2017 Open Whisper Systems. All rights reserved.
//

import UIKit

import SignalMessaging
import PureLayout
import SignalServiceKit
import PromiseKit

@objc
public class ShareViewController: UINavigationController, ShareViewDelegate, SAEFailedViewDelegate {

    private var hasInitialRootViewController = false
    private var isReadyForAppExtensions = false

    var progressPoller: ProgressPoller?
    var loadViewController: SAELoadViewController?

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
        if !isReadyForAppExtensions {
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
        after(seconds: 2).then { () -> Void in
            guard self.presentedViewController == nil else {
                Logger.debug("\(self.logTag) setup completed quickly, no need to present load view controller.")
                return
            }

            Logger.debug("\(self.logTag) setup is slow - showing loading screen")

            let navigationController = UINavigationController(rootViewController: loadViewController)
            self.present(navigationController, animated: true)
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
    func databaseViewRegistrationComplete() {
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

        guard !TSDatabaseView.hasPendingViewRegistrations() else {
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
        self.setViewControllers([viewController], animated: false)
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

    // MARK: ShareViewDelegate, SAEFailedViewDelegate

    public func shareViewWasCompleted() {
        self.dismiss(animated: true) {
            self.extensionContext!.completeRequest(returningItems: [], completionHandler: nil)
        }
    }

    public func shareViewWasCancelled() {
        self.dismiss(animated: true) {
            self.extensionContext!.completeRequest(returningItems: [], completionHandler: nil)
        }
    }

    public func shareViewFailed(error: Error) {
        self.dismiss(animated: true) {
            self.extensionContext!.cancelRequest(withError: error)
        }
    }

    // MARK: Helpers

    private func presentConversationPicker() {
        self.buildAttachment().then { attachment -> Void in
            let conversationPicker = SharingThreadPickerViewController(shareViewDelegate: self)
            let navigationController = UINavigationController(rootViewController: conversationPicker)
            navigationController.isNavigationBarHidden = true
            conversationPicker.attachment = attachment
            if let presentedViewController = self.presentedViewController {
                Logger.debug("\(self.logTag) dismissing \(presentedViewController) before presenting conversation picker")
                self.dismiss(animated: true) {
                    self.present(navigationController, animated: true)
                }
            } else {
                Logger.debug("\(self.logTag) no other modal, presenting conversation picker immediately")
                self.present(navigationController, animated: true)
            }

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

    enum ShareViewControllerError: Error {
        case assertionError(description: String)
        case unsupportedMedia

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

        // Order matters if we want to take advantage of share conversion in loadItem,
        // Though currently we just use "data" for most things and rely on our SignalAttachment
        // class to convert types for us.
        let utiTypes: [String] = [kUTTypeImage as String,
                                  kUTTypeURL as String,
                                  kUTTypeData as String]

        let matchingUtiType = utiTypes.first { (utiType: String) -> Bool in
            itemProvider.hasItemConformingToTypeIdentifier(utiType)
        }

        guard let utiType = matchingUtiType else {
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
                // iOS converts at least some video formats (e.g. com.apple.quicktime-movie) into mp4s as part of the
                // NSItemProvider `loadItem` API.
                // However, for some reason, AVFoundation operations such as generating a preview image and playing
                // the url in the AVMoviePlayer fail on these converted formats until unless we first copy the media
                // into our container. (These operations succeed when resending mp4s received and sent in Signal)
                //
                // I don't understand why this is, and I haven't found any relevant documentation in the NSItemProvider
                // or AVFoundation docs.
                //
                // I *did* verify that the size and sah256 sum of the original url matches that of the copied url.
                // Perhaps the AVFoundation API's require some extra file system permssion we don't have in the
                // passed through URL.
                if MIMETypeUtil.isSupportedVideoFile(itemUrl.path) {
                    return try SignalAttachment.copyToVideoTempDir(url: itemUrl)
                } else {
                    return itemUrl
                }
            }()

            Logger.debug("\(self.logTag) building DataSource with url: \(url)")

            guard let dataSource = DataSourcePath.dataSource(with: url) else {
                throw ShareViewControllerError.assertionError(description: "Unable to read attachment data")
            }
            dataSource.sourceFilename = url.lastPathComponent

            // start with base utiType, but it might be something generic like "image"
            var specificUTIType = utiType
            if url.pathExtension.count > 0 {
                // Determine a more specific utiType based on file extension
                if let typeExtension = MIMETypeUtil.utiType(forFileExtension: url.pathExtension) {
                    Logger.debug("\(self.logTag) utiType based on extension: \(typeExtension)")
                    specificUTIType = typeExtension
                }
            }

            guard !SignalAttachment.isInvalidVideo(dataSource: dataSource, dataUTI: specificUTIType) else {
                // This can happen, e.g. when sharing a quicktime-video from iCloud drive.

                let (promise, exportSession) = SignalAttachment.compressVideoAsMp4(dataSource: dataSource, dataUTI: specificUTIType)

                // Can we move this process to the end of the share flow rather than up front?
                // Currently we aren't able to generate a proper thumbnail or play the video in the app extension without first converting it.
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
}

class ProgressPoller {

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
