//
// Copyright 2017 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import CoreServices
import Intents
public import PureLayout
import SignalServiceKit
public import SignalUI
import UniformTypeIdentifiers

public class ShareViewController: UIViewController, ShareViewDelegate, SAEFailedViewDelegate {

    enum ShareViewControllerError: Error {
        case unsupportedMedia
        case notRegistered
        case obsoleteShare
        case screenLockEnabled
        case tooManyAttachments
        case nilInputItems
        case noInputItems
        case noConformingInputItem
        case nilAttachments
        case noAttachments
        case cannotLoadUIImageObject
        case loadUIImageObjectFailed
        case uiImageMissingOrCorruptImageData
        case cannotLoadURLObject
        case loadURLObjectFailed
        case cannotLoadStringObject
        case loadStringObjectFailed
        case loadDataRepresentationFailed
        case loadInPlaceFileRepresentationFailed
        case nonFileUrl
        case fileUrlWasBplist
    }

    private var hasInitialRootViewController = false
    private var isReadyForAppExtensions = false

    private var progressPoller: ProgressPoller?
    lazy var loadViewController = SAELoadViewController(delegate: self)

    public var shareViewNavigationController: OWSNavigationController?
    private var loadTask: Task<Void, any Error>?

    private lazy var appReadiness = AppReadinessImpl()

    override open func loadView() {
        super.loadView()

        // This should be the first thing we do.
        let appContext = ShareAppExtensionContext(rootViewController: self)
        SetCurrentAppContext(appContext)

        let debugLogger = DebugLogger.shared
        debugLogger.enableTTYLoggingIfNeeded()
        debugLogger.enableFileLogging(appContext: appContext, canLaunchInBackground: false)
        DebugLogger.registerLibsignal()

        Logger.info("")

        // We don't need to use applySignalAppearence in the SAE.

        if appContext.isRunningTests {
            // TODO: Do we need to implement isRunningTests in the SAE context?
            return
        }

        let keychainStorage = KeychainStorageImpl(isUsingProductionService: TSConstants.isUsingProductionService)
        let databaseStorage: SDSDatabaseStorage
        do {
            databaseStorage = try SDSDatabaseStorage(
                appReadiness: appReadiness,
                databaseFileUrl: SDSDatabaseStorage.grdbDatabaseFileUrl,
                keychainStorage: keychainStorage
            )
        } catch {
            self.showNotRegisteredView()
            return
        }
        databaseStorage.grdbStorage.setUpDatabasePathKVO()

        // We shouldn't set up our environment until after we've consulted isReadyForAppExtensions.
        let databaseContinuation = AppSetup().start(
            appContext: appContext,
            appReadiness: appReadiness,
            databaseStorage: databaseStorage,
            paymentsEvents: PaymentsEventsAppExtension(),
            mobileCoinHelper: MobileCoinHelperMinimal(),
            callMessageHandler: NoopCallMessageHandler(),
            currentCallProvider: CurrentCallNoOpProvider(),
            notificationPresenter: NoopNotificationPresenterImpl(),
            incrementalMessageTSAttachmentMigratorFactory: NoOpIncrementalMessageTSAttachmentMigratorFactory(),
            messageBackupErrorPresenterFactory: NoOpMessageBackupErrorPresenterFactory()
        )

        // Configure the rest of the globals before preparing the database.
        SUIEnvironment.shared.setUp(
            appReadiness: appReadiness,
            authCredentialManager: databaseContinuation.authCredentialManager
        )

        databaseContinuation.prepareDatabase().done(on: DispatchQueue.main) { finalContinuation in
            switch finalContinuation.finish(willResumeInProgressRegistration: false) {
            case .corruptRegistrationState:
                self.showNotRegisteredView()
            case nil:
                self.setAppIsReady()
            }
        }

        let shareViewNavigationController = OWSNavigationController()
        shareViewNavigationController.presentationController?.delegate = self
        shareViewNavigationController.delegate = self
        self.shareViewNavigationController = shareViewNavigationController

        // Don't display load screen immediately, in hopes that we can avoid it altogether.
        Guarantee.after(seconds: 0.8).done { [weak self] in
            AssertIsOnMainThread()

            guard let strongSelf = self else { return }
            guard strongSelf.presentedViewController == nil else {
                Logger.debug("setup completed quickly, no need to present load view controller.")
                return
            }

            Logger.debug("setup is slow - showing loading screen")
            strongSelf.showPrimaryViewController(strongSelf.loadViewController)
        }

        // We don't need to use "screen protection" in the SAE.

        NotificationCenter.default.addObserver(self,
                                               selector: #selector(registrationStateDidChange),
                                               name: .registrationStateDidChange,
                                               object: nil)
        NotificationCenter.default.addObserver(self,
                                               selector: #selector(owsApplicationWillEnterForeground),
                                               name: .OWSApplicationWillEnterForeground,
                                               object: nil)
        NotificationCenter.default.addObserver(self,
                                               selector: #selector(applicationDidEnterBackground),
                                               name: .OWSApplicationDidEnterBackground,
                                               object: nil)

        Logger.info("completed.")
    }

    deinit {
        Logger.info("deinit")
    }

    @objc
    private func applicationDidEnterBackground() {
        AssertIsOnMainThread()

        Logger.info("")

        if ScreenLock.shared.isScreenLockEnabled() {
            Logger.info("dismissing.")
            dismissAndCompleteExtension(animated: false, error: ShareViewControllerError.screenLockEnabled)
        }
    }

    private func activate() {
        AssertIsOnMainThread()

        Logger.debug("")

        // We don't need to use "screen protection" in the SAE.

        ensureRootViewController()

        // Always check prekeys after app launches, and sometimes check on app activation.
        SSKEnvironment.shared.databaseStorageRef.read { tx in
            if DependenciesBridge.shared.tsAccountManager.registrationState(tx: tx.asV2Read).isRegistered {
                DependenciesBridge.shared.preKeyManager.checkPreKeysIfNecessary(tx: tx.asV2Read)
            }
        }

        // We don't need to use RTCInitializeSSL() in the SAE.

        if DependenciesBridge.shared.tsAccountManager.registrationStateWithMaybeSneakyTransaction.isRegistered {
            Logger.info("running post launch block for registered user: \(String(describing: DependenciesBridge.shared.tsAccountManager.localIdentifiersWithMaybeSneakyTransaction?.aciAddress))")
        } else {
            Logger.info("running post launch block for unregistered user.")

            // We don't need to update the app icon badge number in the SAE.

            // We don't need to prod the ChatConnectionManager in the SAE.
        }

        if DependenciesBridge.shared.tsAccountManager.registrationStateWithMaybeSneakyTransaction.isRegistered {
            DispatchQueue.main.async { [weak self] in
                guard self != nil else { return }
                Logger.info("running post launch block for registered user: \(String(describing: DependenciesBridge.shared.tsAccountManager.localIdentifiersWithMaybeSneakyTransaction?.aciAddress))")

                // We don't need to use the ChatConnectionManager in the SAE.

                // TODO: Re-enable when system contact fetching uses less memory.
                // self.contactsManager.fetchSystemContactsOnceIfAlreadyAuthorized()

                // We don't need to fetch messages in the SAE.

                // We don't need to use OWSSyncPushTokensJob in the SAE.
            }
        }
    }

    private func setAppIsReady() {
        Logger.debug("")
        AssertIsOnMainThread()
        owsPrecondition(!appReadiness.isAppReady)

        // We don't need to use LaunchJobs in the SAE.

        // Note that this does much more than set a flag; it will also run all deferred blocks.
        appReadiness.setAppIsReady()

        if DependenciesBridge.shared.tsAccountManager.registrationStateWithMaybeSneakyTransaction.isRegistered {
            Logger.info("localAddress: \(String(describing: DependenciesBridge.shared.tsAccountManager.localIdentifiersWithMaybeSneakyTransaction?.aciAddress))")

            // We don't need to use messageFetcherJob in the SAE.

            // We don't need to use SyncPushTokensJob in the SAE.
        }

        AppVersionImpl.shared.saeLaunchDidComplete()

        ensureRootViewController()

        // We don't need to fetch the local profile in the SAE
    }

    @objc
    private func registrationStateDidChange() {
        AssertIsOnMainThread()

        Logger.debug("")

        if DependenciesBridge.shared.tsAccountManager.registrationStateWithMaybeSneakyTransaction.isRegistered {
            Logger.info("localAddress: \(String(describing: DependenciesBridge.shared.tsAccountManager.localIdentifiersWithMaybeSneakyTransaction?.aciAddress))")

            // We don't need to use ExperienceUpgradeFinder in the SAE.

            // We don't need to use OWSDisappearingMessagesJob in the SAE.
        }
    }

    private func ensureRootViewController() {
        AssertIsOnMainThread()

        Logger.debug("")

        guard appReadiness.isAppReady else {
            return
        }
        guard !hasInitialRootViewController else {
            return
        }
        hasInitialRootViewController = true

        Logger.info("Presenting initial root view controller")

        if ScreenLock.shared.isScreenLockEnabled() {
            presentScreenLock()
        } else {
            presentContentView()
        }
    }

    private func presentContentView() {
        AssertIsOnMainThread()

        Logger.debug("")

        Logger.info("Presenting content view")

        guard DependenciesBridge.shared.tsAccountManager.registrationStateWithMaybeSneakyTransaction.isRegistered else {
            showNotRegisteredView()
            return
        }

        let localProfileExists = SSKEnvironment.shared.databaseStorageRef.read { transaction in
            return SSKEnvironment.shared.profileManagerRef.localProfileExists(with: transaction)
        }
        guard localProfileExists else {
            // This is a rare edge case, but we want to ensure that the user
            // has already saved their local profile key in the main app.
            showNotReadyView()
            return
        }

        buildAttachmentsAndPresentConversationPicker()
        // We don't use the AppUpdateNag in the SAE.
    }

    // MARK: Error Views

    private func showNotReadyView() {
        AssertIsOnMainThread()

        let failureTitle = OWSLocalizedString("SHARE_EXTENSION_NOT_YET_MIGRATED_TITLE",
                                             comment: "Title indicating that the share extension cannot be used until the main app has been launched at least once.")
        let failureMessage = OWSLocalizedString("SHARE_EXTENSION_NOT_YET_MIGRATED_MESSAGE",
                                               comment: "Message indicating that the share extension cannot be used until the main app has been launched at least once.")
        showErrorView(title: failureTitle, message: failureMessage)
    }

    private func showNotRegisteredView() {
        AssertIsOnMainThread()

        let failureTitle = OWSLocalizedString("SHARE_EXTENSION_NOT_REGISTERED_TITLE",
                                             comment: "Title indicating that the share extension cannot be used until the user has registered in the main app.")
        let failureMessage = OWSLocalizedString("SHARE_EXTENSION_NOT_REGISTERED_MESSAGE",
                                               comment: "Message indicating that the share extension cannot be used until the user has registered in the main app.")
        showErrorView(title: failureTitle, message: failureMessage)
    }

    private func showErrorView(title: String, message: String) {
        AssertIsOnMainThread()

        let viewController = SAEFailedViewController(delegate: self, title: title, message: message)

        let navigationController = UINavigationController()
        navigationController.presentationController?.delegate = self
        navigationController.setViewControllers([viewController], animated: false)
        if self.presentedViewController == nil {
            Logger.debug("presenting modally: \(viewController)")
            self.present(navigationController, animated: true)
        } else {
            owsFailDebug("modal already presented. swapping modal content for: \(viewController)")
            assert(self.presentedViewController == navigationController)
        }
    }

    // MARK: View Lifecycle

    override open func viewDidLoad() {
        super.viewDidLoad()

        Logger.debug("")

        if isReadyForAppExtensions {
            appReadiness.runNowOrWhenAppDidBecomeReadySync { [weak self] in
                AssertIsOnMainThread()
                self?.activate()
            }
        }
    }

    override open func viewWillAppear(_ animated: Bool) {
        Logger.debug("")

        super.viewWillAppear(animated)
    }

    override open func viewDidAppear(_ animated: Bool) {
        Logger.debug("")

        super.viewDidAppear(animated)
    }

    override open func viewWillDisappear(_ animated: Bool) {
        Logger.debug("")

        super.viewWillDisappear(animated)
        loadTask?.cancel()
        loadTask = nil
    }

    @objc
    private func owsApplicationWillEnterForeground() throws {
        AssertIsOnMainThread()

        Logger.debug("")

        // If a user unregisters in the main app, the SAE should shut down
        // immediately.
        guard !DependenciesBridge.shared.tsAccountManager.registrationStateWithMaybeSneakyTransaction.isRegistered else {
            // If user is registered, do nothing.
            return
        }
        guard let shareViewNavigationController = shareViewNavigationController else {
            owsFailDebug("Missing shareViewNavigationController")
            return
        }
        guard let firstViewController = shareViewNavigationController.viewControllers.first else {
            // If no view has been presented yet, do nothing.
            return
        }
        if firstViewController is SAEFailedViewController {
            // If root view is an error view, do nothing.
            return
        }
        throw ShareViewControllerError.notRegistered
    }

    // MARK: ShareViewDelegate, SAEFailedViewDelegate

    public func shareViewWasUnlocked() {
        Logger.info("")

        presentContentView()
    }

    public func shareViewWasCompleted() {
        Logger.info("")
        dismissAndCompleteExtension(animated: true, error: nil)
    }

    public func shareViewWasCancelled() {
        Logger.info("")
        dismissAndCompleteExtension(animated: true, error: ShareViewControllerError.obsoleteShare)
    }

    public func shareViewFailed(error: Error) {
        owsFailDebug("Error: \(error)")
        dismissAndCompleteExtension(animated: true, error: error)
    }

    private func dismissAndCompleteExtension(animated: Bool, error: Error?) {
        let extensionContext = self.extensionContext
        dismiss(animated: animated) {
            AssertIsOnMainThread()

            if let error {
                extensionContext?.cancelRequest(withError: error)
            } else {
                extensionContext?.completeRequest(returningItems: [], completionHandler: nil)
            }

            // Share extensions reside in a process that may be reused between usages.
            // That isn't safe; the codebase is full of statics (e.g. singletons) which
            // we can't easily clean up.
            Logger.info("ExitShareExtension")
            Logger.flush()
            exit(0)
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
        AssertIsOnMainThread()

        guard let shareViewNavigationController = shareViewNavigationController else {
            owsFailDebug("Missing shareViewNavigationController")
            return
        }
        shareViewNavigationController.setViewControllers([viewController], animated: true)
        if self.presentedViewController == nil {
            Logger.debug("presenting modally: \(viewController)")
            self.present(shareViewNavigationController, animated: true)
        } else {
            Logger.debug("modal already presented. swapping modal content for: \(viewController)")
            assert(self.presentedViewController == shareViewNavigationController)
        }
    }

    private lazy var conversationPicker = SharingThreadPickerViewController(shareViewDelegate: self)
    private func buildAttachmentsAndPresentConversationPicker() {
        let selectedThread: TSThread?
        if let intent = extensionContext?.intent as? INSendMessageIntent,
           let threadUniqueId = intent.conversationIdentifier {
            selectedThread = SSKEnvironment.shared.databaseStorageRef.read { TSThread.anyFetch(uniqueId: threadUniqueId, transaction: $0) }
        } else {
            selectedThread = nil
        }

        // If we have a pre-selected thread, we wait to show the approval view
        // until the attachments have been built. Otherwise, we'll present it
        // immediately and tell it what attachments we're sharing once we've
        // finished building them.
        if selectedThread == nil {
            showPrimaryViewController(conversationPicker)
        }

        loadTask?.cancel()
        loadTask = Task {
            do {
                guard let inputItems = self.extensionContext?.inputItems as? [NSExtensionItem] else {
                    throw ShareViewControllerError.nilInputItems
                }
                #if DEBUG
                for (inputItemIndex, inputItem) in inputItems.enumerated() {
                    Logger.debug("- inputItems[\(inputItemIndex)]")
                    for (itemProvidersIndex, itemProviders) in inputItem.attachments!.enumerated() {
                        Logger.debug("  - itemProviders[\(itemProvidersIndex)]")
                        for typeIdentifier in itemProviders.registeredTypeIdentifiers {
                            Logger.debug("    - \(typeIdentifier)")
                        }
                    }
                }
                #endif
                let inputItem = try Self.selectExtensionItem(inputItems)
                guard let itemProviders = inputItem.attachments else {
                    throw ShareViewControllerError.nilAttachments
                }
                guard !itemProviders.isEmpty else {
                    throw ShareViewControllerError.noAttachments
                }

                let typedItemProviders = try Self.typedItemProviders(for: itemProviders)
                self.conversationPicker.areAttachmentStoriesCompatPrecheck = typedItemProviders.allSatisfy { $0.isStoriesCompatible }
                let attachments = try await self.buildAttachments(for: typedItemProviders)
                try Task.checkCancellation()

                // Make sure the user is not trying to share more than our attachment limit.
                guard attachments.filter({ !$0.isConvertibleToTextMessage }).count <= SignalAttachment.maxAttachmentsAllowed else {
                    throw ShareViewControllerError.tooManyAttachments
                }

                self.progressPoller = nil

                Logger.info("Setting picker attachments: \(attachments)")
                self.conversationPicker.attachments = attachments

                if let selectedThread = selectedThread {
                    let approvalVC = try self.conversationPicker.buildApprovalViewController(for: selectedThread)
                    self.showPrimaryViewController(approvalVC)
                }

            } catch ShareViewControllerError.tooManyAttachments {
                let format = OWSLocalizedString("IMAGE_PICKER_CAN_SELECT_NO_MORE_TOAST_FORMAT",
                                                comment: "Momentarily shown to the user when attempting to select more images than is allowed. Embeds {{max number of items}} that can be shared.")

                let alertTitle = String(format: format, OWSFormat.formatInt(SignalAttachment.maxAttachmentsAllowed))

                OWSActionSheets.showActionSheet(
                    title: alertTitle,
                    buttonTitle: CommonStrings.cancelButton
                ) { _ in
                    self.shareViewWasCancelled()
                }
            } catch {
                let alertTitle = OWSLocalizedString("SHARE_EXTENSION_UNABLE_TO_BUILD_ATTACHMENT_ALERT_TITLE",
                                                    comment: "Shown when trying to share content to a Signal user for the share extension. Followed by failure details.")

                OWSActionSheets.showActionSheet(
                    title: alertTitle,
                    message: error.userErrorDescription,
                    buttonTitle: CommonStrings.cancelButton
                ) { _ in
                    self.shareViewWasCancelled()
                }
                owsFailDebug("building attachment failed with error: \(error)")
            }
        }
    }

    private func presentScreenLock() {
        AssertIsOnMainThread()

        let screenLockUI = SAEScreenLockViewController(shareViewDelegate: self)
        Logger.debug("presentScreenLock: \(screenLockUI)")
        showPrimaryViewController(screenLockUI)
        Logger.info("showing screen lock")
    }

    private static func selectExtensionItem(_ extensionItems: [NSExtensionItem]) throws -> NSExtensionItem {
        if extensionItems.isEmpty {
            throw ShareViewControllerError.noInputItems
        }
        if extensionItems.count == 1 {
            return extensionItems.first!
        }

        // Handle safari sharing images and PDFs as two separate items one with the object to share and the other as the URL of the data.
        for extensionItem in extensionItems {
            for attachment in extensionItem.attachments ?? [] {
                if attachment.hasItemConformingToTypeIdentifier(UTType.data.identifier)
                    || attachment.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier)
                    || attachment.hasItemConformingToTypeIdentifier("com.apple.pkpass") {
                    return extensionItem
                }
            }
        }
        throw ShareViewControllerError.noConformingInputItem
    }

    private struct TypedItemProvider {
        enum ItemType {
            case movie
            case image
            case webUrl
            case fileUrl
            case contact
            case text
            case pdf
            case pkPass
            case json
            case data

            var typeIdentifier: String {
                switch self {
                case .movie:
                    return UTType.movie.identifier
                case .image:
                    return UTType.image.identifier
                case .webUrl:
                    return UTType.url.identifier
                case .fileUrl:
                    return UTType.fileURL.identifier
                case .contact:
                    return UTType.vCard.identifier
                case .text:
                    return UTType.text.identifier
                case .pdf:
                    return UTType.pdf.identifier
                case .pkPass:
                    return "com.apple.pkpass"
                case .json:
                    return UTType.json.identifier
                case .data:
                    return UTType.data.identifier
                }
            }
        }

        let itemProvider: NSItemProvider
        let itemType: ItemType

        var isWebUrl: Bool {
            itemType == .webUrl
        }

        var isVisualMedia: Bool {
            itemType == .image || itemType == .movie
        }

        var isStoriesCompatible: Bool {
            switch itemType {
            case .movie, .image, .webUrl, .text:
                return true
            case .fileUrl, .contact, .pdf, .pkPass, .json, .data:
                return false
            }
        }
    }

    private static func typedItemProviders(for itemProviders: [NSItemProvider]) throws -> [TypedItemProvider] {
        // for some data types the OS is just awful and apparently says they conform to something else but then returns useless versions of the information
        // - com.topografix.gpx
        //     conforms to public.text, but when asking the OS for text it returns a file URL instead
        let forcedDataTypeIdentifiers: [String] = ["com.topografix.gpx"]
        // due to UT conformance fallbacks the order these are checked is important; more specific types need to come earlier in the list than their fallbacks
        let itemTypeOrder: [TypedItemProvider.ItemType] = [.movie, .image, .contact, .json, .text, .pdf, .pkPass, .fileUrl, .webUrl, .data]
        let candidates: [TypedItemProvider] = try itemProviders.map { itemProvider in
            for typeIdentifier in forcedDataTypeIdentifiers {
                if itemProvider.hasItemConformingToTypeIdentifier(typeIdentifier) {
                    return TypedItemProvider(itemProvider: itemProvider, itemType: .data)
                }
            }
            for itemType in itemTypeOrder {
                if itemProvider.hasItemConformingToTypeIdentifier(itemType.typeIdentifier) {
                    return TypedItemProvider(itemProvider: itemProvider, itemType: itemType)
                }
            }
            owsFailDebug("unexpected share item: \(itemProvider)")
            throw ShareViewControllerError.unsupportedMedia
        }

        // URL shares can come in with text preview and favicon attachments so we ignore other attachments with a URL
        if let webUrlCandidate = candidates.first(where: { $0.isWebUrl }) {
            return [webUrlCandidate]
        }

        // only 1 attachment is supported unless it's visual media so select just the first or just the visual media elements with a preference for visual media
        let visualMediaCandidates = candidates.filter { $0.isVisualMedia }
        return visualMediaCandidates.isEmpty ? Array(candidates.prefix(1)) : visualMediaCandidates
    }

    nonisolated private func buildAttachments(for typedItemProviders: [TypedItemProvider]) async throws -> [SignalAttachment] {

        // FIXME: does not use a task group because SignalAttachment likes to load things into RAM and resize them; doing this in parallel can exhaust available RAM
        var result: [SignalAttachment] = []
        for typedItemProvider in typedItemProviders {
            result.append(try await self.buildAttachment(for: typedItemProvider))
        }
        return result
    }

    nonisolated private func buildAttachment(for typedItemProvider: TypedItemProvider) async throws -> SignalAttachment {
        let itemProvider = typedItemProvider.itemProvider
        switch typedItemProvider.itemType {
        case .image:
            // some apps send a usable file to us and some throw a UIImage at us, the UIImage can come in either directly
            // or as a bplist containing the NSKeyedArchiver output of a UIImage. the code below executes the following
            // order of attempts to load the input in the right way:
            //   1) try attaching the image from a file so we don't have to load the image into RAM in the common case
            //   2) try to load a UIImage directly in the case that is what was sent over
            //   3) try to NSKeyedUnarchive NSData directly into a UIImage
            do {
                return try await self.buildFileAttachment(fromItemProvider: itemProvider, forTypeIdentifier: typedItemProvider.itemType.typeIdentifier)
            } catch SignalAttachmentError.couldNotParseImage, ShareViewControllerError.fileUrlWasBplist {
                Logger.warn("failed to parse image directly from file; checking for loading UIImage directly")
                let image: UIImage = try await Self.loadObjectWithKeyedUnarchiverFallback(fromItemProvider: itemProvider, forTypeIdentifier: typedItemProvider.itemType.typeIdentifier, cannotLoadError: .cannotLoadUIImageObject, failedLoadError: .loadUIImageObjectFailed)
                return try Self.createAttachment(withImage: image)
            }
        case .movie, .pdf, .data:
            return try await self.buildFileAttachment(fromItemProvider: itemProvider, forTypeIdentifier: typedItemProvider.itemType.typeIdentifier)
        case .fileUrl, .json:
            let url: NSURL = try await Self.loadObjectWithKeyedUnarchiverFallback(fromItemProvider: itemProvider, forTypeIdentifier: TypedItemProvider.ItemType.fileUrl.typeIdentifier, cannotLoadError: .cannotLoadURLObject, failedLoadError: .loadURLObjectFailed)
            let attachment = try Self.copyAttachment(fromUrl: url as URL)
            return try await self.compressVideo(attachment: attachment)
        case .webUrl:
            let url: NSURL = try await Self.loadObjectWithKeyedUnarchiverFallback(fromItemProvider: itemProvider, forTypeIdentifier: typedItemProvider.itemType.typeIdentifier, cannotLoadError: .cannotLoadURLObject, failedLoadError: .loadURLObjectFailed)
            return try Self.createAttachment(withText: (url as URL).absoluteString)
        case .contact:
            let contactData = try await Self.loadDataRepresentation(fromItemProvider: itemProvider, forTypeIdentifier: UTType.contact.identifier)
            let dataSource = DataSourceValue(contactData, utiType: UTType.contact.identifier)
            let attachment = SignalAttachment.attachment(dataSource: dataSource, dataUTI: UTType.contact.identifier)
            attachment.isConvertibleToContactShare = true
            if let attachmentError = attachment.error {
                throw attachmentError
            }
            return attachment
        case .text:
            let text: NSString = try await Self.loadObjectWithKeyedUnarchiverFallback(fromItemProvider: itemProvider, forTypeIdentifier: typedItemProvider.itemType.typeIdentifier, cannotLoadError: .cannotLoadStringObject, failedLoadError: .loadStringObjectFailed)
            return try Self.createAttachment(withText: text as String)
        case .pkPass:
            let typeIdentifier = "com.apple.pkpass"
            let pkPass = try await Self.loadDataRepresentation(fromItemProvider: itemProvider, forTypeIdentifier: typeIdentifier)
            let dataSource = DataSourceValue(pkPass, fileExtension: "pkpass")
            let attachment = SignalAttachment.attachment(dataSource: dataSource, dataUTI: typeIdentifier)
            if let attachmentError = attachment.error {
                throw attachmentError
            }
            return attachment
        }
    }

    nonisolated private static func copyAttachment(fromUrl url: URL, defaultTypeIdentifier: String = UTType.data.identifier) throws -> SignalAttachment {
        guard let dataSource = try? DataSourcePath(fileUrl: url, shouldDeleteOnDeallocation: false) else {
            throw ShareViewControllerError.nonFileUrl
        }
        dataSource.sourceFilename = url.lastPathComponent
        let utiType = MimeTypeUtil.utiTypeForFileExtension(url.pathExtension) ?? defaultTypeIdentifier
        let attachment = SignalAttachment.attachment(dataSource: dataSource, dataUTI: utiType)
        if let attachmentError = attachment.error {
            throw attachmentError
        }
        return try attachment.cloneAttachment()
    }

    nonisolated private func compressVideo(attachment: SignalAttachment) async throws -> SignalAttachment {
        if attachment.isVideoThatNeedsCompression() {
            // TODO: Move waiting for this export to the end of the share flow rather than up front
            let compressedAttachment = try await SignalAttachment.compressVideoAsMp4(dataSource: attachment.dataSource, dataUTI: attachment.dataUTI, sessionCallback: { exportSession in
                let progressPoller = ProgressPoller(timeInterval: 0.1, ratioCompleteBlock: { return exportSession.progress })

                self.progressPoller = progressPoller
                progressPoller.startPolling()

                self.loadViewController.progress = progressPoller.progress
            })
            if let attachmentError = compressedAttachment.error {
                throw attachmentError
            }
            return compressedAttachment
        } else {
            return attachment
        }
    }

    nonisolated private func buildFileAttachment(fromItemProvider itemProvider: NSItemProvider, forTypeIdentifier typeIdentifier: String) async throws -> SignalAttachment {
        let attachment: SignalAttachment = try await withCheckedThrowingContinuation { continuation in
            _ = itemProvider.loadInPlaceFileRepresentation(forTypeIdentifier: typeIdentifier, completionHandler: { fileUrl, _, error in
                if let error {
                    continuation.resume(throwing: error)
                } else if let fileUrl {
                    if Self.isBplist(url: fileUrl) {
                        continuation.resume(throwing: ShareViewControllerError.fileUrlWasBplist)
                    } else {
                        do {
                            // NOTE: Compression here rather than creating an additional temp file would be nice but blocking this completion handler for video encoding is probably not a good way to go.
                            continuation.resume(returning: try Self.copyAttachment(fromUrl: fileUrl, defaultTypeIdentifier: typeIdentifier))
                        } catch {
                            continuation.resume(throwing: error)
                        }
                    }
                } else {
                    continuation.resume(throwing: ShareViewControllerError.loadInPlaceFileRepresentationFailed)
                }
            })
        }

        if let attachmentError = attachment.error {
            throw attachmentError
        }

        return try await self.compressVideo(attachment: attachment)
    }

    nonisolated private static func loadDataRepresentation(fromItemProvider itemProvider: NSItemProvider, forTypeIdentifier typeIdentifier: String) async throws -> Data {
        try await withCheckedThrowingContinuation { continuation in
            _ = itemProvider.loadDataRepresentation(forTypeIdentifier: typeIdentifier) { data, error in
                if let error {
                    continuation.resume(throwing: error)
                } else if let data {
                    continuation.resume(returning: data)
                } else {
                    continuation.resume(throwing: ShareViewControllerError.loadDataRepresentationFailed)
                }
            }
        }
    }

    nonisolated private static func loadObjectWithKeyedUnarchiverFallback<T>(fromItemProvider itemProvider: NSItemProvider,
                                                                             forTypeIdentifier typeIdentifier: String,
                                                                             cannotLoadError: ShareViewControllerError,
                                                                             failedLoadError: ShareViewControllerError) async throws -> T
    where T: NSItemProviderReading, T: NSCoding, T: NSObject {
        do {
            guard itemProvider.canLoadObject(ofClass: T.self) else {
                throw cannotLoadError
            }
            return try await withCheckedThrowingContinuation { continuation in
                _ = itemProvider.loadObject(ofClass: T.self) { object, error in
                    if let error {
                        continuation.resume(throwing: error)
                    } else if let typedObject = object as? T {
                        continuation.resume(returning: typedObject)
                    } else {
                        continuation.resume(throwing: failedLoadError)
                    }
                }
            }
        } catch {
            let data = try await loadDataRepresentation(fromItemProvider: itemProvider, forTypeIdentifier: typeIdentifier)
            if let result = try? NSKeyedUnarchiver.unarchivedObject(ofClass: T.self, from: data) {
                return result
            } else {
                throw error
            }
        }
    }

    nonisolated private static func createAttachment(withText text: String) throws -> SignalAttachment {
        let dataSource = DataSourceValue(oversizeText: text)
        let attachment = SignalAttachment.attachment(dataSource: dataSource, dataUTI: UTType.text.identifier)
        if let attachmentError = attachment.error {
            throw attachmentError
        }
        attachment.isConvertibleToTextMessage = true
        return attachment
    }

    nonisolated private static func createAttachment(withImage image: UIImage) throws -> SignalAttachment {
        guard let imagePng = image.pngData() else {
            throw ShareViewControllerError.uiImageMissingOrCorruptImageData
        }
        let type = UTType.png
        let dataSource = DataSourceValue(imagePng, utiType: type.identifier)
        let attachment = SignalAttachment.attachment(dataSource: dataSource, dataUTI: type.identifier)
        if let attachmentError = attachment.error {
            throw attachmentError
        }
        return attachment
    }

    nonisolated private static func isBplist(url: URL) -> Bool {
        if let handle = try? FileHandle(forReadingFrom: url) {
            let data = handle.readData(ofLength: 6)
            return data == "bplist".data(using: .utf8)
        } else {
            return false
        }
    }
}

extension ShareViewController: UIAdaptivePresentationControllerDelegate {
    public func presentationControllerDidDismiss(_ presentationController: UIPresentationController) {
        shareViewWasCancelled()
    }
}

// MARK: -

extension ShareViewController: UINavigationControllerDelegate {

    public func navigationController(_ navigationController: UINavigationController, willShow viewController: UIViewController, animated: Bool) {
        updateNavigationBarVisibility(for: viewController, in: navigationController, animated: animated)
    }

    public func navigationController(_ navigationController: UINavigationController, didShow viewController: UIViewController, animated: Bool) {
        updateNavigationBarVisibility(for: viewController, in: navigationController, animated: animated)
    }

    private func updateNavigationBarVisibility(for viewController: UIViewController,
                                               in navigationController: UINavigationController,
                                               animated: Bool) {
        switch viewController {
        case is AttachmentApprovalViewController:
            navigationController.setNavigationBarHidden(true, animated: animated)
        default:
            navigationController.setNavigationBarHidden(false, animated: animated)
        }
    }
}

// Exposes a Progress object, whose progress is updated by polling the return of a given block
private class ProgressPoller: NSObject {

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
            owsFailDebug("already started timer")
            return
        }

        self.timer = WeakTimer.scheduledTimer(timeInterval: timeInterval, target: self, userInfo: nil, repeats: true) { [weak self] (timer) in
            guard let strongSelf = self else {
                return
            }

            let completedUnitCount = Int64(strongSelf.ratioCompleteBlock() * Float(strongSelf.progressTotalUnitCount))
            strongSelf.progress.completedUnitCount = completedUnitCount

            if completedUnitCount == strongSelf.progressTotalUnitCount {
                Logger.debug("progress complete")
                timer.invalidate()
            }
        }
    }
}
