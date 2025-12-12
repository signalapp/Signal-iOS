//
// Copyright 2017 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import CoreServices
import Intents
import PureLayout
import SignalServiceKit
public import SignalUI
import UniformTypeIdentifiers

public class ShareViewController: OWSNavigationController, ShareViewDelegate, SAEFailedViewDelegate {

    enum ShareViewControllerError: Error {
        case obsoleteShare
        case screenLockEnabled
        case tooManyAttachments
        case nilInputItems
        case noInputItems
        case noConformingInputItem
        case nilAttachments
        case noAttachments
    }

    public var shareViewNavigationController: OWSNavigationController { self }

    private lazy var appReadiness = AppReadinessImpl()

    private var connectionTokens = [OWSChatConnection.ConnectionToken]()

    private var initialLoadViewController: SAELoadViewController?

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

        let initialLoadViewController = SAELoadViewController(
            delegate: self,
            shouldMimicRecipientPicker: self.extensionContext?.intent == nil,
        )
        self.setViewControllers([initialLoadViewController], animated: false)
        self.initialLoadViewController = initialLoadViewController
    }

    public override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)

        if let initialLoadViewController = self.initialLoadViewController.take() {
            // Wait one run loop to ensure the loading indicator is visible if setUp
            // blocks the main thread.
            DispatchQueue.main.async {
                Task { try await self.setUp(initialLoadViewController: initialLoadViewController) }
            }
        }
    }

    private func setUp(initialLoadViewController: SAELoadViewController) async throws {
        let appContext = CurrentAppContext()

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

        let databaseContinuation = await AppSetup()
            .start(
                appContext: appContext,
                databaseStorage: databaseStorage,
            )
            .migrateDatabaseSchema()
            .initGlobals(
                appReadiness: appReadiness,
                backupArchiveErrorPresenterFactory: NoOpBackupArchiveErrorPresenterFactory(),
                deviceBatteryLevelManager: nil,
                deviceSleepManager: nil,
                paymentsEvents: PaymentsEventsAppExtension(),
                mobileCoinHelper: MobileCoinHelperMinimal(),
                callMessageHandler: NoopCallMessageHandler(),
                currentCallProvider: CurrentCallNoOpProvider(),
                notificationPresenter: NoopNotificationPresenterImpl(),
            )

        // Configure the rest of the globals before preparing the database.
        SUIEnvironment.shared.setUp(
            appReadiness: appReadiness,
            authCredentialManager: databaseContinuation.authCredentialManager
        )

        let finalContinuation = await databaseContinuation.migrateDatabaseData()
        finalContinuation.runLaunchTasksIfNeededAndReloadCaches()
        switch finalContinuation.setUpLocalIdentifiers(
            willResumeInProgressRegistration: false,
            canInitiateRegistration: false
        ) {
        case .corruptRegistrationState:
            self.showNotRegisteredView()
            return
        case nil:
            self.setAppIsReady()
        }

        var didDisplaceInitialLoadViewController = false

        if ScreenLock.shared.isScreenLockEnabled() {
            let didUnlock = await withCheckedContinuation { continuation in
                let viewController = SAEScreenLockViewController { didUnlock in
                    continuation.resume(returning: didUnlock)
                }
                self.setViewControllers([viewController], animated: false)
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

        // We need the unidentified connection for bulk identity key lookups.
        let chatConnectionManager = DependenciesBridge.shared.chatConnectionManager
        self.connectionTokens.append(chatConnectionManager.requestUnidentifiedConnection())

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
            self.setViewControllers([conversationPicker], animated: false)
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

        let typedItems: [TypedItem]
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
                self.setViewControllers([loadViewControllerToDisplay], animated: false)
            }()
            typedItems = try await buildAndValidateAttachments(
                for: typedItemProviders,
                setProgress: { loadViewControllerForProgress?.progress = $0 }
            )
        } catch {
            self.presentAttachmentError(error)
            return
        }

        Logger.info("Setting picker attachments: \(typedItems.count)")
        conversationPicker.typedItems = typedItems

        if let preSelectedThread {
            let approvalViewController = try conversationPicker.buildApprovalViewController(for: preSelectedThread)
            self.setViewControllers([approvalViewController], animated: false)

            // If you're sharing to a specific thread, the picker view controller isn't
            // added to the view hierarchy, but it's the "brains" of the sending
            // operation and must not be deallocated. Tie its lifetime to the lifetime
            // of the view controller that's visible.
            ObjectRetainer.retainObject(conversationPicker, forLifetimeOf: approvalViewController)
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
            dismissAndCompleteExtension(error: ShareViewControllerError.screenLockEnabled)
        }
    }

    private func setAppIsReady() {
        AssertIsOnMainThread()
        owsPrecondition(!appReadiness.isAppReady)

        // Note that this does much more than set a flag; it will also run all deferred blocks.
        appReadiness.setAppIsReady()

        let localAci = DependenciesBridge.shared.tsAccountManager.localIdentifiersWithMaybeSneakyTransaction?.aci
        Logger.info("localAci: \(localAci?.logString ?? "<none>")")

        let appVersion = AppVersionImpl.shared
        appVersion.dumpToLog()
        appVersion.updateFirstVersionIfNeeded()
        appVersion.saeLaunchDidComplete()

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

        self.setViewControllers([viewController], animated: false)
    }

    // MARK: ShareViewDelegate, SAEFailedViewDelegate

    public func shareViewWillSend() {
        let chatConnectionManager = DependenciesBridge.shared.chatConnectionManager
        self.connectionTokens.append(chatConnectionManager.requestIdentifiedConnection())
    }

    public func shareViewWasCompleted() {
        Logger.info("")
        dismissAndCompleteExtension(error: nil)
    }

    public func shareViewWasCancelled() {
        Logger.info("")
        dismissAndCompleteExtension(error: ShareViewControllerError.obsoleteShare)
    }

    public func shareViewFailed(error: Error) {
        owsFailDebug("Error: \(error)")
        dismissAndCompleteExtension(error: error)
    }

    private func dismissAndCompleteExtension(error: Error?) {
        AssertIsOnMainThread()

        let extensionContext = self.extensionContext
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

    // MARK: Helpers

    private func fetchPreSelectedThread() -> TSThread? {
        let hasIntent = self.extensionContext?.intent != nil
        Logger.info("hasIntent? \(hasIntent)")
        if let threadUniqueId = (self.extensionContext?.intent as? INSendMessageIntent)?.conversationIdentifier {
            let result = SSKEnvironment.shared.databaseStorageRef.read { TSThread.anyFetch(uniqueId: threadUniqueId, transaction: $0) }
            Logger.info("hasThread? \(result != nil)")
            return result
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

        let candidates = try itemProviders.map(TypedItemProvider.make(for:))

        // URL shares can come in with text preview and favicon attachments so we ignore other attachments with a URL
        if let webUrlCandidate = candidates.first(where: { $0.isWebUrl }) {
            return [webUrlCandidate]
        }

        // only 1 attachment is supported unless it's visual media so select just the first or just the visual media elements with a preference for visual media
        let visualMediaCandidates = candidates.filter { $0.isVisualMedia }
        return visualMediaCandidates.isEmpty ? Array(candidates.prefix(1)) : visualMediaCandidates
    }

    private func buildAndValidateAttachments(
        for typedItemProviders: [TypedItemProvider],
        setProgress: @MainActor (Progress) -> Void
    ) async throws -> [TypedItem] {
        let progress = Progress(totalUnitCount: Int64(typedItemProviders.count))

        let itemsAndProgresses = typedItemProviders.map {
            let itemProgress = Progress(totalUnitCount: 10_000)
            progress.addChild(itemProgress, withPendingUnitCount: 1)
            return ($0, itemProgress)
        }

        setProgress(progress)

        let typedItems = try await self.buildAttachments(for: itemsAndProgresses)
        try Task.checkCancellation()

        // Make sure the user is not trying to share more than our attachment limit.
        guard typedItems.count <= SignalAttachment.maxAttachmentsAllowed else {
            throw ShareViewControllerError.tooManyAttachments
        }

        return typedItems
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

    private nonisolated func buildAttachments(for itemsAndProgresses: [(TypedItemProvider, Progress)]) async throws -> [TypedItem] {
        // FIXME: does not use a task group because SignalAttachment likes to load things into RAM and resize them; doing this in parallel can exhaust available RAM
        var result: [TypedItem] = []
        for (typedItemProvider, progress) in itemsAndProgresses {
            result.append(try await typedItemProvider.buildAttachment(progress: progress))
        }
        return result
    }

    public override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)

        // If we're disappearing because we presented something else (e.g., image
        // editing tools), don't cancel the share extension.
        guard self.presentedViewController == nil else {
            return
        }

        shareViewWasCancelled()
    }
}
