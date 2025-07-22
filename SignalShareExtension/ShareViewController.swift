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
        case obsoleteShare
        case screenLockEnabled
        case tooManyAttachments
        case nilInputItems
        case noInputItems
        case noConformingInputItem
        case nilAttachments
        case noAttachments
    }

    public var shareViewNavigationController: OWSNavigationController?

    private lazy var appReadiness = AppReadinessImpl()

    private var connectionTokens = [OWSChatConnection.ConnectionToken]()

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
            backupArchiveErrorPresenterFactory: NoOpBackupArchiveErrorPresenterFactory(),
            databaseStorage: databaseStorage,
            deviceBatteryLevelManager: nil,
            deviceSleepManager: nil,
            paymentsEvents: PaymentsEventsAppExtension(),
            mobileCoinHelper: MobileCoinHelperMinimal(),
            callMessageHandler: NoopCallMessageHandler(),
            currentCallProvider: CurrentCallNoOpProvider(),
            notificationPresenter: NoopNotificationPresenterImpl(),
            incrementalMessageTSAttachmentMigratorFactory: NoOpIncrementalMessageTSAttachmentMigratorFactory(),
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

            // We need the unidentified connection for bulk identity key lookups.
            if OWSChatConnection.canAppUseSocketsToMakeRequests {
                let chatConnectionManager = DependenciesBridge.shared.chatConnectionManager
                self.connectionTokens.append(chatConnectionManager.requestUnidentifiedConnection(shouldReconnectIfConnectedElsewhere: true))
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

    public func shareViewWillSend() {
        if OWSChatConnection.canAppUseSocketsToMakeRequests {
            let chatConnectionManager = DependenciesBridge.shared.chatConnectionManager
            self.connectionTokens.append(chatConnectionManager.requestIdentifiedConnection(shouldReconnectIfConnectedElsewhere: true))
        }
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
            self.present(shareViewNavigationController, animated: true)
        } else {
            assert(self.presentedViewController == shareViewNavigationController)
        }
    }

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

    nonisolated private func buildAttachments(for itemsAndProgresses: [(TypedItemProvider, Progress)]) async throws -> [SignalAttachment] {
        // FIXME: does not use a task group because SignalAttachment likes to load things into RAM and resize them; doing this in parallel can exhaust available RAM
        var result: [SignalAttachment] = []
        for (typedItemProvider, progress) in itemsAndProgresses {
            result.append(try await typedItemProvider.buildAttachment(progress: progress))
        }
        return result
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
