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
        case fileUrlWasBplist
    }

    public var shareViewNavigationController: OWSNavigationController?

    private lazy var appReadiness = AppReadinessImpl()

    override open func loadView() {
        super.loadView()

        // This should be the first thing we do.
        let appContext = ShareAppExtensionContext(rootViewController: self)
        SetCurrentAppContext(appContext, isRunningTests: false)

        let debugLogger = DebugLogger.shared
        debugLogger.enableTTYLoggingIfNeeded()
        debugLogger.enableFileLogging(appContext: appContext, canLaunchInBackground: false)
        DebugLogger.registerLibsignal()

        Logger.info("")

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

        let databaseContinuation = AppSetup().start(
            appContext: appContext,
            appReadiness: appReadiness,
            databaseStorage: databaseStorage,
            deviceSleepManager: nil,
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

        let shareViewNavigationController = OWSNavigationController()
        shareViewNavigationController.presentationController?.delegate = self
        shareViewNavigationController.delegate = self
        self.shareViewNavigationController = shareViewNavigationController

        Task {
            let initialLoadViewController = SAELoadViewController(delegate: self)
            var didDisplaceInitialLoadViewController = false
            async let _ = { @MainActor () async throws -> Void in
                // Don't display load screen immediately because loading the database and
                // preparing attachments (if the recipient is pre-selected) will usually be
                // fast enough that we can avoid it altogether. If you haven't run GRDB
                // migrations in a while or have selected a long video, though, you'll
                // likely see the load screen after 800ms.
                try await Task.sleep(nanoseconds: 0.8.clampedNanoseconds)
                guard self.presentedViewController == nil else {
                    return
                }
                self.showPrimaryViewController(initialLoadViewController)
            }()

            let finalContinuation = await databaseContinuation.prepareDatabase()
            switch finalContinuation.finish(willResumeInProgressRegistration: false) {
            case .corruptRegistrationState:
                self.showNotRegisteredView()
                return
            case nil:
                self.setAppIsReady()
            }

            if ScreenLock.shared.isScreenLockEnabled() {
                let didUnlock = await withCheckedContinuation { continuation in
                    let viewController = SAEScreenLockViewController { didUnlock in
                        continuation.resume(returning: didUnlock)
                    }
                    self.showPrimaryViewController(viewController)
                }
                guard didUnlock else {
                    self.shareViewWasCancelled()
                    return
                }
                // If we show the Screen Lock UI, that'll displace the loading view
                // controller or prevent it from being shown.
                didDisplaceInitialLoadViewController = true
            }

            // Prepare the attachments.

            let typedItemProviders: [TypedItemProvider]
            do {
                typedItemProviders = try buildTypedItemProviders()
            } catch {
                self.presentAttachmentError(error)
                return
            }

            let conversationPicker: SharingThreadPickerViewController
            conversationPicker = SharingThreadPickerViewController(
                areAttachmentStoriesCompatPrecheck: typedItemProviders.allSatisfy { $0.isStoriesCompatible },
                shareViewDelegate: self
            )

            let preSelectedThread = self.fetchPreSelectedThread()

            let loadViewControllerToDisplay: SAELoadViewController?
            let loadViewControllerForProgress: SAELoadViewController?

            // If we have a pre-selected thread, we wait to show the approval view
            // until the attachments have been built. Otherwise, we'll present it
            // immediately and tell it what attachments we're sharing once we've
            // finished building them.
            if preSelectedThread == nil {
                self.showPrimaryViewController(conversationPicker)
                // We show a progress spinner on the recipient picker.
                loadViewControllerToDisplay = nil
                loadViewControllerForProgress = nil
            } else if didDisplaceInitialLoadViewController {
                // We hit this branch when isScreenLockEnabled() == true. In this case, we
                // need a new instance because the initial one has already been
                // shown/dismissed.
                loadViewControllerToDisplay = SAELoadViewController(delegate: self)
                loadViewControllerForProgress = loadViewControllerToDisplay
            } else {
                // We don't need to show anything (it'll be shown by the block at the
                // beginning of this Task), but we do want to hook up progress reporting.
                loadViewControllerToDisplay = nil
                loadViewControllerForProgress = initialLoadViewController
            }

            let attachments: [SignalAttachment]
            do {
                // If buildAndValidateAttachments takes longer than 200ms, we want to show
                // the new load view. If it takes less than 200ms, we'll exit out of this
                // `do` block, that will cancel the `async let`, and then we'll leave the
                // primary view controller alone as a result.
                async let _ = { @MainActor () async throws -> Void in
                    guard let loadViewControllerToDisplay else {
                        return
                    }
                    try await Task.sleep(nanoseconds: 0.2.clampedNanoseconds)
                    // Check for cancellation on the main thread to ensure mutual exclusion
                    // with the the code outside of this do block.
                    try Task.checkCancellation()
                    self.showPrimaryViewController(loadViewControllerToDisplay)
                }()
                attachments = try await buildAndValidateAttachments(
                    for: typedItemProviders,
                    setProgress: { loadViewControllerForProgress?.progress = $0 }
                )
            } catch {
                self.presentAttachmentError(error)
                return
            }

            Logger.info("Setting picker attachments: \(attachments)")
            conversationPicker.attachments = attachments

            if let preSelectedThread {
                let approvalViewController = try conversationPicker.buildApprovalViewController(for: preSelectedThread)
                self.showPrimaryViewController(approvalViewController)

                // If you're sharing to a specific thread, the picker view controller isn't
                // added to the view hierarchy, but it's the "brains" of the sending
                // operation and must not be deallocated. Tie its lifetime to the lifetime
                // of the view controller that's visible.
                ObjectRetainer.retainObject(conversationPicker, forLifetimeOf: approvalViewController)
            }
        }

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(applicationDidEnterBackground),
            name: .OWSApplicationDidEnterBackground,
            object: nil
        )

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

    private func setAppIsReady() {
        AssertIsOnMainThread()
        owsPrecondition(!appReadiness.isAppReady)

        // Note that this does much more than set a flag; it will also run all deferred blocks.
        appReadiness.setAppIsReady()

        let localAci = DependenciesBridge.shared.tsAccountManager.localIdentifiersWithMaybeSneakyTransaction?.aci
        Logger.info("localAci: \(localAci?.logString ?? "<none>")")

        AppVersionImpl.shared.saeLaunchDidComplete()

        Logger.info("")
    }

    // MARK: Error Views

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
            self.present(navigationController, animated: true)
        } else {
            owsFailDebug("modal already presented. swapping modal content for: \(type(of: viewController))")
            assert(self.presentedViewController == navigationController)
        }
    }

    // MARK: ShareViewDelegate, SAEFailedViewDelegate

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
            self.present(shareViewNavigationController, animated: true)
        } else {
            assert(self.presentedViewController == shareViewNavigationController)
        }
    }

    private func fetchPreSelectedThread() -> TSThread? {
        if let threadUniqueId = (self.extensionContext?.intent as? INSendMessageIntent)?.conversationIdentifier {
            return SSKEnvironment.shared.databaseStorageRef.read { TSThread.anyFetch(uniqueId: threadUniqueId, transaction: $0) }
        } else {
            return nil
        }
    }

    private func buildTypedItemProviders() throws -> [TypedItemProvider] {
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

        return try Self.typedItemProviders(for: itemProviders)
    }

    private func buildAndValidateAttachments(
        for typedItemProviders: [TypedItemProvider],
        setProgress: @MainActor (Progress) -> Void
    ) async throws -> [SignalAttachment] {
        let progress = Progress(totalUnitCount: Int64(typedItemProviders.count))

        let itemsAndProgresses = typedItemProviders.map {
            let itemProgress = Progress(totalUnitCount: 10_000)
            progress.addChild(itemProgress, withPendingUnitCount: 1)
            return ($0, itemProgress)
        }

        setProgress(progress)

        let attachments = try await self.buildAttachments(for: itemsAndProgresses)
        try Task.checkCancellation()

        // Make sure the user is not trying to share more than our attachment limit.
        guard attachments.filter({ !$0.isConvertibleToTextMessage }).count <= SignalAttachment.maxAttachmentsAllowed else {
            throw ShareViewControllerError.tooManyAttachments
        }

        return attachments
    }

    private func presentAttachmentError(_ error: any Error) {
        switch error {
        case ShareViewControllerError.tooManyAttachments:
            let format = OWSLocalizedString(
                "IMAGE_PICKER_CAN_SELECT_NO_MORE_TOAST_FORMAT",
                comment: "Momentarily shown to the user when attempting to select more images than is allowed. Embeds {{max number of items}} that can be shared."
            )

            let alertTitle = String(format: format, OWSFormat.formatInt(SignalAttachment.maxAttachmentsAllowed))

            OWSActionSheets.showActionSheet(
                title: alertTitle,
                buttonTitle: CommonStrings.cancelButton
            ) { _ in
                self.shareViewWasCancelled()
            }
        default:
            let alertTitle = OWSLocalizedString(
                "SHARE_EXTENSION_UNABLE_TO_BUILD_ATTACHMENT_ALERT_TITLE",
                comment: "Shown when trying to share content to a Signal user for the share extension. Followed by failure details."
            )

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
            // Apple docs and runtime checks seem to imply "public.plain-text"
            // should be able to be loaded from an NSItemProvider as
            // "public.text", but in practice it fails with:
            // "A string could not be instantiated because of an unknown error."
            case plainText
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
                case .plainText:
                    return UTType.plainText.identifier
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
            case .movie, .image, .webUrl, .plainText, .text:
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
        let itemTypeOrder: [TypedItemProvider.ItemType] = [.movie, .image, .contact, .json, .plainText, .text, .pdf, .pkPass, .fileUrl, .webUrl, .data]
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

    nonisolated private func buildAttachments(for itemsAndProgresses: [(TypedItemProvider, Progress)]) async throws -> [SignalAttachment] {
        // FIXME: does not use a task group because SignalAttachment likes to load things into RAM and resize them; doing this in parallel can exhaust available RAM
        var result: [SignalAttachment] = []
        for (typedItemProvider, progress) in itemsAndProgresses {
            result.append(try await self.buildAttachment(for: typedItemProvider, progress: progress))
        }
        return result
    }

    nonisolated private func buildAttachment(for typedItemProvider: TypedItemProvider, progress: Progress) async throws -> SignalAttachment {
        // Whenever this finishes, mark its progress as fully complete. This
        // handles item providers that can't provide partial progress updates.
        defer {
            progress.completedUnitCount = progress.totalUnitCount
        }

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
                return try await self.buildFileAttachment(fromItemProvider: itemProvider, forTypeIdentifier: typedItemProvider.itemType.typeIdentifier, progress: progress)
            } catch SignalAttachmentError.couldNotParseImage, ShareViewControllerError.fileUrlWasBplist {
                Logger.warn("failed to parse image directly from file; checking for loading UIImage directly")
                let image: UIImage = try await Self.loadObjectWithKeyedUnarchiverFallback(fromItemProvider: itemProvider, forTypeIdentifier: typedItemProvider.itemType.typeIdentifier, cannotLoadError: .cannotLoadUIImageObject, failedLoadError: .loadUIImageObjectFailed)
                return try Self.createAttachment(withImage: image)
            }
        case .movie, .pdf, .data:
            return try await self.buildFileAttachment(fromItemProvider: itemProvider, forTypeIdentifier: typedItemProvider.itemType.typeIdentifier, progress: progress)
        case .fileUrl, .json:
            let url: NSURL = try await Self.loadObjectWithKeyedUnarchiverFallback(fromItemProvider: itemProvider, forTypeIdentifier: TypedItemProvider.ItemType.fileUrl.typeIdentifier, cannotLoadError: .cannotLoadURLObject, failedLoadError: .loadURLObjectFailed)

            let (dataSource, dataUTI) = try Self.copyFileUrl(
                fileUrl: url as URL,
                defaultTypeIdentifier: UTType.data.identifier
            )

            return try await compressVideoIfNecessary(
                dataSource: dataSource,
                dataUTI: dataUTI,
                progress: progress
            )
        case .webUrl:
            let url: NSURL = try await Self.loadObjectWithKeyedUnarchiverFallback(fromItemProvider: itemProvider, forTypeIdentifier: typedItemProvider.itemType.typeIdentifier, cannotLoadError: .cannotLoadURLObject, failedLoadError: .loadURLObjectFailed)
            return try Self.createAttachment(withText: (url as URL).absoluteString)
        case .contact:
            let contactData = try await Self.loadDataRepresentation(fromItemProvider: itemProvider, forTypeIdentifier: typedItemProvider.itemType.typeIdentifier)
            let dataSource = DataSourceValue(contactData, utiType: typedItemProvider.itemType.typeIdentifier)
            let attachment = SignalAttachment.attachment(dataSource: dataSource, dataUTI: typedItemProvider.itemType.typeIdentifier)
            attachment.isConvertibleToContactShare = true
            if let attachmentError = attachment.error {
                throw attachmentError
            }
            return attachment
        case .plainText, .text:
            let text: NSString = try await Self.loadObjectWithKeyedUnarchiverFallback(fromItemProvider: itemProvider, forTypeIdentifier: typedItemProvider.itemType.typeIdentifier, cannotLoadError: .cannotLoadStringObject, failedLoadError: .loadStringObjectFailed)
            return try Self.createAttachment(withText: text as String)
        case .pkPass:
            let pkPass = try await Self.loadDataRepresentation(fromItemProvider: itemProvider, forTypeIdentifier: typedItemProvider.itemType.typeIdentifier)
            let dataSource = DataSourceValue(pkPass, utiType: typedItemProvider.itemType.typeIdentifier)
            let attachment = SignalAttachment.attachment(dataSource: dataSource, dataUTI: typedItemProvider.itemType.typeIdentifier)
            if let attachmentError = attachment.error {
                throw attachmentError
            }
            return attachment
        }
    }

    nonisolated private static func copyFileUrl(
        fileUrl: URL,
        defaultTypeIdentifier: String
    ) throws -> (DataSource, dataUTI: String) {
        guard fileUrl.isFileURL else {
            throw OWSAssertionError("Unexpectedly not a file URL: \(fileUrl)")
        }

        let copiedUrl = OWSFileSystem.temporaryFileUrl(fileExtension: fileUrl.pathExtension)
        try FileManager.default.copyItem(at: fileUrl, to: copiedUrl)

        let dataSource = try DataSourcePath(fileUrl: copiedUrl, shouldDeleteOnDeallocation: true)
        dataSource.sourceFilename = fileUrl.lastPathComponent

        let dataUTI = MimeTypeUtil.utiTypeForFileExtension(fileUrl.pathExtension) ?? defaultTypeIdentifier

        return (dataSource, dataUTI)
    }

    nonisolated private func compressVideoIfNecessary(
        dataSource: DataSource,
        dataUTI: String,
        progress: Progress
    ) async throws -> SignalAttachment {
        if SignalAttachment.isVideoThatNeedsCompression(
            dataSource: dataSource,
            dataUTI: dataUTI
        ) {
            // TODO: Move waiting for this export to the end of the share flow rather than up front
            var progressPoller: ProgressPoller?
            defer {
                progressPoller?.stopPolling()
            }
            let compressedAttachment = try await SignalAttachment.compressVideoAsMp4(
                dataSource: dataSource,
                dataUTI: dataUTI,
                sessionCallback: { exportSession in
                    progressPoller = ProgressPoller(progress: progress, pollInterval: 0.1, fractionCompleted: { return exportSession.progress })
                    progressPoller?.startPolling()
                }
            )

            if let attachmentError = compressedAttachment.error {
                throw attachmentError
            }

            return compressedAttachment
        } else {
            let attachment = SignalAttachment.attachment(dataSource: dataSource, dataUTI: dataUTI)

            if let attachmentError = attachment.error {
                throw attachmentError
            }

            return attachment
        }
    }

    nonisolated private func buildFileAttachment(fromItemProvider itemProvider: NSItemProvider, forTypeIdentifier typeIdentifier: String, progress: Progress) async throws -> SignalAttachment {
        let (dataSource, dataUTI): (DataSource, String) = try await withCheckedThrowingContinuation { continuation in
            _ = itemProvider.loadInPlaceFileRepresentation(forTypeIdentifier: typeIdentifier, completionHandler: { fileUrl, _, error in
                if let error {
                    continuation.resume(throwing: error)
                } else if let fileUrl {
                    if Self.isBplist(url: fileUrl) {
                        continuation.resume(throwing: ShareViewControllerError.fileUrlWasBplist)
                    } else {
                        do {
                            // NOTE: Compression here rather than creating an additional temp file would be nice but blocking this completion handler for video encoding is probably not a good way to go.
                            continuation.resume(returning: try Self.copyFileUrl(fileUrl: fileUrl, defaultTypeIdentifier: typeIdentifier))
                        } catch {
                            continuation.resume(throwing: error)
                        }
                    }
                } else {
                    continuation.resume(throwing: ShareViewControllerError.loadInPlaceFileRepresentationFailed)
                }
            })
        }

        return try await compressVideoIfNecessary(dataSource: dataSource, dataUTI: dataUTI, progress: progress)
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
            return data == Data("bplist".utf8)
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
    private let progress: Progress
    private let pollInterval: TimeInterval
    private let fractionCompleted: () -> Float

    init(progress: Progress, pollInterval: TimeInterval, fractionCompleted: @escaping () -> Float) {
        self.progress = progress
        self.pollInterval = pollInterval
        self.fractionCompleted = fractionCompleted
    }

    private var timer: Timer?

    func stopPolling() {
        timer?.invalidate()
    }

    func startPolling() {
        guard self.timer == nil else {
            owsFailDebug("already started timer")
            return
        }

        self.timer = WeakTimer.scheduledTimer(timeInterval: pollInterval, target: self, userInfo: nil, repeats: true) { [weak self] (timer) in
            guard let self else {
                timer.invalidate()
                return
            }

            let fractionCompleted = self.fractionCompleted()
            self.progress.completedUnitCount = Int64(fractionCompleted * Float(self.progress.totalUnitCount))
        }
    }
}
