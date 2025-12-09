//
// Copyright 2019 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import LibSignalClient
import Photos
import PhotosUI
import SignalServiceKit
import SignalUI

protocol SendMediaNavDelegate: AnyObject {

    func sendMediaNavDidCancel(_ sendMediaNavigationController: SendMediaNavigationController)

    func sendMediaNav(_ sendMediaNavigationController: SendMediaNavigationController, didApproveAttachments approvedAttachments: ApprovedAttachments, messageBody: MessageBody?)

    func sendMediaNav(_ sendMediaNavigationController: SendMediaNavigationController, didFinishWithTextAttachment textAttachment: UnsentTextAttachment)

    func sendMediaNav(_ sendMediaNavigationController: SendMediaNavigationController, didChangeMessageBody newMessageBody: MessageBody?)

    func sendMediaNav(_ sendMediaNavigationController: SendMediaNavigationController, didChangeViewOnceState isViewOnce: Bool)
}

protocol SendMediaNavDataSource: AnyObject {

    func sendMediaNavInitialMessageBody(_ sendMediaNavigationController: SendMediaNavigationController) -> MessageBody?

    var sendMediaNavTextInputContextIdentifier: String? { get }

    var sendMediaNavRecipientNames: [String] { get }

    func sendMediaNavMentionableAcis(tx: DBReadTransaction) -> [Aci]

    func sendMediaNavMentionCacheInvalidationKey() -> String
}

class CameraFirstCaptureNavigationController: SendMediaNavigationController {

    override var requiresContactPickerToProceed: Bool {
        true
    }

    override var canSendToStories: Bool { StoryManager.areStoriesEnabled }

    private var cameraFirstCaptureSendFlow: CameraFirstCaptureSendFlow!

    class func cameraFirstModal(
        storiesOnly: Bool = false,
        hasQuotedReplyDraft: Bool,
        delegate: CameraFirstCaptureDelegate,
    ) -> CameraFirstCaptureNavigationController {
        let navController = CameraFirstCaptureNavigationController(hasQuotedReplyDraft: hasQuotedReplyDraft)
        navController.setViewControllers([navController.captureViewController], animated: false)

        let cameraFirstCaptureSendFlow = CameraFirstCaptureSendFlow(storiesOnly: storiesOnly, delegate: delegate)
        navController.cameraFirstCaptureSendFlow = cameraFirstCaptureSendFlow
        navController.sendMediaNavDelegate = cameraFirstCaptureSendFlow
        navController.sendMediaNavDataSource = cameraFirstCaptureSendFlow

        navController.storiesOnly = storiesOnly

        return navController
    }
}

class SendMediaNavigationController: OWSNavigationController {

    fileprivate var requiresContactPickerToProceed: Bool {
        false
    }

    fileprivate var canSendToStories: Bool { false }
    fileprivate var storiesOnly: Bool = false

    private let hasQuotedReplyDraft: Bool

    fileprivate init(hasQuotedReplyDraft: Bool) {
        self.hasQuotedReplyDraft = hasQuotedReplyDraft
        super.init()
    }

    // MARK: - Overrides

    override var childForStatusBarStyle: UIViewController? {
        topViewController
    }

    // MARK: -

    weak var sendMediaNavDelegate: SendMediaNavDelegate?
    weak var sendMediaNavDataSource: SendMediaNavDataSource?

    class func showingCameraFirst(hasQuotedReplyDraft: Bool) -> SendMediaNavigationController {
        let navController = SendMediaNavigationController(hasQuotedReplyDraft: hasQuotedReplyDraft)
        navController.setViewControllers([navController.captureViewController], animated: false)
        return navController
    }

    fileprivate var nativePickerToPresent: PHPickerViewController?

    private static func phPickerConfiguration(cameraAttachmentCount: Int) -> PHPickerConfiguration {
        var config = PHPickerConfiguration(photoLibrary: .shared())
        config.preferredAssetRepresentationMode = .current
        config.selectionLimit = SignalAttachment.maxAttachmentsAllowed - cameraAttachmentCount
        config.selection = .ordered
        return config
    }

    class func showingNativePicker(hasQuotedReplyDraft: Bool) -> SendMediaNavigationController {
        // We want to present the photo picker in a sheet and then have the
        // editor appear behind it after you select photos, so present this
        // navigation controller as transparent with an empty view, then when
        // you select photos, `showApprovalViewController` will make it appear
        // behind the dismissing sheet and transition to the editor.
        let navController = SendMediaNavigationController(hasQuotedReplyDraft: hasQuotedReplyDraft)
        navController.pushViewController(UIViewController(), animated: false)
        navController.view.layer.opacity = 0
        navController.modalPresentationStyle = .overCurrentContext

        let config = Self.phPickerConfiguration(cameraAttachmentCount: 0)
        let vc = PHPickerViewController(configuration: config)
        vc.delegate = navController

        navController.nativePickerToPresent = vc

        return navController
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        if let nativePicker = self.nativePickerToPresent {
            nativePicker.modalPresentationStyle = .formSheet
            nativePicker.presentationController?.delegate = self
            self.present(nativePicker, animated: true)
            self.nativePickerToPresent = nil
        }
    }

    class func showingApprovalWithPickedLibraryMedia(
        asset: PHAsset,
        attachment: PreviewableAttachment,
        hasQuotedReplyDraft: Bool,
        delegate: SendMediaNavDelegate,
        dataSource: SendMediaNavDataSource
    ) -> SendMediaNavigationController {
        let navController = SendMediaNavigationController(hasQuotedReplyDraft: hasQuotedReplyDraft)
        navController.sendMediaNavDelegate = delegate
        navController.sendMediaNavDataSource = dataSource
        navController.modalPresentationStyle = .overCurrentContext

        let approvalItem = AttachmentApprovalItem(attachment: attachment, canSave: false)
        navController.pendingAttachments.append(PendingAttachment(
            source: .systemLibrary(systemIdentifier: asset.localIdentifier),
            approvalItem: approvalItem,
        ))

        navController.showApprovalViewController()

        return navController
    }

    private func fadeTo(viewControllers: [UIViewController], duration: CFTimeInterval) {
        AssertIsOnMainThread()

        let transition: CATransition = CATransition()
        transition.duration = duration
        transition.type = CATransitionType.fade
        view.layer.add(transition, forKey: nil)
        setViewControllers(viewControllers, animated: false)
    }

    private var pendingAttachments: [PendingAttachment] = []

    // MARK: - Child View Controllers

    fileprivate lazy var captureViewController: PhotoCaptureViewController = {
        let viewController = PhotoCaptureViewController()
        viewController.delegate = self
        viewController.dataSource = self
        return viewController
    }()

    var hasUnsavedChanges: Bool {
        (topViewController as? AttachmentApprovalViewController)?.currentPageViewController?.canSaveMedia ?? false
    }

    private func showApprovalViewController() {
        guard let sendMediaNavDataSource = sendMediaNavDataSource else {
            owsFailDebug("sendMediaNavDataSource was unexpectedly nil")
            return
        }

        let hasCameraCapture = viewControllers.first is PhotoCaptureViewController

        var options: AttachmentApprovalViewControllerOptions = [.canAddMore]
        if !hasCameraCapture {
            options.insert(.hasCancel)
        }
        if requiresContactPickerToProceed {
            options.insert(.isNotFinalScreen)
        }
        if canSendToStories, storiesOnly {
            options.insert(.disallowViewOnce)
        }
        if hasQuotedReplyDraft {
            options.insert(.disallowViewOnce)
        }
        let approvalViewController = AttachmentApprovalViewController.loadWithSneakyTransaction(
            attachmentApprovalItems: pendingAttachments.map(\.approvalItem),
            options: options,
        )
        approvalViewController.approvalDelegate = self
        approvalViewController.approvalDataSource = self
        approvalViewController.stickerSheetDelegate = self
        let messageBody = sendMediaNavDataSource.sendMediaNavInitialMessageBody(self)
        approvalViewController.setMessageBody(messageBody, txProvider: DependenciesBridge.shared.db.readTxProvider)

        self.view.layer.opacity = 1

        let newViewControllers = if hasCameraCapture {
            viewControllers + [approvalViewController]
        } else {
            [approvalViewController]
        }

        fadeTo(viewControllers: newViewControllers, duration: 0.3)
    }

    private func didRequestExit(dontAbandonText: String) {
        if self.pendingAttachments.isEmpty {
            self.sendMediaNavDelegate?.sendMediaNavDidCancel(self)
        } else {
            let alert = ActionSheetController()
            alert.overrideUserInterfaceStyle = .dark

            let confirmAbandonText = OWSLocalizedString(
                "SEND_MEDIA_CONFIRM_ABANDON_ALBUM",
                comment: "alert action, confirming the user wants to exit the media flow and abandon any photos they've taken",
            )
            let confirmAbandonAction = ActionSheetAction(
                title: confirmAbandonText,
                style: .destructive,
                handler: { [weak self] _ in
                    guard let self = self else { return }
                    self.sendMediaNavDelegate?.sendMediaNavDidCancel(self)
                },
            )
            alert.addAction(confirmAbandonAction)
            let dontAbandonAction = ActionSheetAction(
                title: dontAbandonText,
                style: .default,
                handler: { _ in },
            )
            alert.addAction(dontAbandonAction)
            self.presentActionSheet(alert)
        }
    }
}

extension SendMediaNavigationController {

    // MARK: - Too Many

    func showTooManySelectedToast() {
        let toastFormat = OWSLocalizedString("IMAGE_PICKER_CAN_SELECT_NO_MORE_TOAST_%d", tableName: "PluralAware",
                                            comment: "Momentarily shown to the user when attempting to select more images than is allowed. Embeds {{max number of items}} that can be shared.")

        let toastText = String.localizedStringWithFormat(toastFormat, SignalAttachment.maxAttachmentsAllowed)
        let toastController = ToastController(text: toastText)
        toastController.presentToastView(from: .bottom, of: view, inset: view.layoutMargins.bottom + 10)
    }
}

extension SendMediaNavigationController: PhotoCaptureViewControllerDelegate {

    func photoCaptureViewControllerDidFinish(_ photoCaptureViewController: PhotoCaptureViewController) {
        owsPrecondition(numberOfMediaItems > 0)
        showApprovalViewController()
    }

    func photoCaptureViewController(
        _ photoCaptureViewController: PhotoCaptureViewController,
        didFinishWithTextAttachment textAttachment: UnsentTextAttachment,
    ) {
        sendMediaNavDelegate?.sendMediaNav(self, didFinishWithTextAttachment: textAttachment)
    }

    func photoCaptureViewControllerDidCancel(_ photoCaptureViewController: PhotoCaptureViewController) {
        let dontAbandonText = OWSLocalizedString("SEND_MEDIA_RETURN_TO_CAMERA", comment: "alert action when the user decides not to cancel the media flow after all.")
        didRequestExit(dontAbandonText: dontAbandonText)
    }

    func photoCaptureViewControllerViewWillAppear(_ photoCaptureViewController: PhotoCaptureViewController) {
        if
            photoCaptureViewController.captureMode == .single,
            self.pendingAttachments.count == 1,
            case .camera = self.pendingAttachments.last?.source
        {
            // User is navigating back to the camera screen, indicating they want to discard the previously captured item.
            self.pendingAttachments = []
        }
    }

    func photoCaptureViewControllerDidTryToCaptureTooMany(_ photoCaptureViewController: PhotoCaptureViewController) {
        showTooManySelectedToast()
    }

    func photoCaptureViewControllerCanCaptureMoreItems(_ photoCaptureViewController: PhotoCaptureViewController) -> Bool {
        return self.pendingAttachments.count < SignalAttachment.maxAttachmentsAllowed
    }

    func photoCaptureViewControllerDidRequestPresentPhotoLibrary(_ photoCaptureViewController: PhotoCaptureViewController) {
        presentAdditionalPhotosPicker()
    }

    func photoCaptureViewController(
        _ photoCaptureViewController: PhotoCaptureViewController,
        didRequestSwitchCaptureModeTo captureMode: PhotoCaptureViewController.CaptureMode,
        completion: @escaping (Bool) -> Void,
    ) {
        // .multi always can be enabled.
        guard captureMode == .single else {
            completion(true)
            return
        }
        // Disable immediately if there's no media attachments yet.
        guard !self.pendingAttachments.isEmpty else {
            completion(true)
            return
        }
        // Ask to delete all existing media attachments.
        let title = OWSLocalizedString(
            "SEND_MEDIA_TURN_OFF_MM_TITLE",
            comment: "In-app camera: title for the prompt to turn off multi-mode that will cause previously taken photos to be discarded.",
        )
        let message = OWSLocalizedString(
            "SEND_MEDIA_TURN_OFF_MM_MESSAGE",
            comment: "In-app camera: message for the prompt to turn off multi-mode that will cause previously taken photos to be discarded.",
        )
        let buttonTitle = OWSLocalizedString(
            "SEND_MEDIA_TURN_OFF_MM_BUTTON",
            comment: "In-app camera: confirmation button in the prompt to turn off multi-mode.",
        )
        let actionSheet = ActionSheetController(title: title, message: message)
        actionSheet.overrideUserInterfaceStyle = .dark
        actionSheet.addAction(ActionSheetAction(title: buttonTitle, style: .destructive) { _ in
            self.pendingAttachments.removeAll()
            completion(true)
        })
        actionSheet.addAction(ActionSheetAction(title: CommonStrings.cancelButton, style: .cancel) { _ in
            completion(false)
        })
        presentActionSheet(actionSheet)
    }

    func photoCaptureViewControllerCanShowTextEditor(_ photoCaptureViewController: PhotoCaptureViewController) -> Bool {
        return canSendToStories
    }
}

extension SendMediaNavigationController: PhotoCaptureViewControllerDataSource {

    var numberOfMediaItems: Int {
        return self.pendingAttachments.count
    }

    func addMedia(attachment: PreviewableAttachment) {
        self.pendingAttachments.append(PendingAttachment(
            source: .camera,
            approvalItem: AttachmentApprovalItem(attachment: attachment, canSave: true),
        ))
    }
}

extension SendMediaNavigationController: PHPickerViewControllerDelegate {
    private struct PHPickerResultsLoadResult {
        let resolvablePendingAttachments: [() async throws -> PendingAttachment]
        let didAddAttachments: Bool
    }

    /// Load the `results` in the order they are given.
    private func loadOrderedPHPickerResults(_ results: [PHPickerResult]) -> PHPickerResultsLoadResult {
        var didAddAttachments = false

        let pendingAttachmentByAssetIdentifier: [String: PendingAttachment] = Dictionary(
            uniqueKeysWithValues: self.pendingAttachments.compactMap { (pendingAttachment) -> (String, PendingAttachment)? in
                switch pendingAttachment.source {
                case .camera:
                    return nil
                case .systemLibrary(let systemIdentifier):
                    return (systemIdentifier, pendingAttachment)
                }
            }
        )

        let resolvablePendingAttachments = results.compactMap { (result) -> (() async throws -> PendingAttachment)? in
            guard let assetIdentifier = result.assetIdentifier else {
                owsFailDebug("can't select asset without an identifier")
                return nil
            }
            if let pendingAttachment = pendingAttachmentByAssetIdentifier[assetIdentifier] {
                return {
                    return pendingAttachment
                }
            } else {
                didAddAttachments = true
                return {
                    let attachment = try await TypedItemProvider.buildVisualMediaAttachment(forItemProvider: result.itemProvider)
                    let approvalItem = AttachmentApprovalItem(attachment: attachment, canSave: false)
                    return PendingAttachment(source: .systemLibrary(systemIdentifier: assetIdentifier), approvalItem: approvalItem)
                }
            }
        }

        return PHPickerResultsLoadResult(
            resolvablePendingAttachments: resolvablePendingAttachments,
            didAddAttachments: didAddAttachments,
        )
    }

    /// Load the `results` on top of the existing `pendingAttachments`.
    private func loadUnorderedPHPickerResults(_ results: [PHPickerResult]) -> PHPickerResultsLoadResult {
        let selectedAssetIdentifiers = Set(results.compactMap(\.assetIdentifier))
        var existingAssetIdentifiers = Set<String>()

        // Keep any attachments from the camera or that are still selected.
        var resolvablePendingAttachments = [() async throws -> PendingAttachment]()
        for pendingAttachment in self.pendingAttachments {
            let shouldKeep: Bool
            switch pendingAttachment.source {
            case .camera:
                shouldKeep = true
            case .systemLibrary(let systemIdentifier):
                existingAssetIdentifiers.insert(systemIdentifier)
                shouldKeep = selectedAssetIdentifiers.contains(systemIdentifier)
            }
            if shouldKeep {
                resolvablePendingAttachments.append({ return pendingAttachment })
            }
        }

        // Add any newly-selected attachments
        var didAddAttachments = false
        for result in results {
            guard let assetIdentifier = result.assetIdentifier else {
                owsFailDebug("can't select asset without an identifier")
                continue
            }
            if existingAssetIdentifiers.contains(assetIdentifier) {
                continue
            }
            didAddAttachments = true
            resolvablePendingAttachments.append({
                let attachment = try await TypedItemProvider.buildVisualMediaAttachment(forItemProvider: result.itemProvider)
                let approvalItem = AttachmentApprovalItem(attachment: attachment, canSave: false)
                return PendingAttachment(source: .systemLibrary(systemIdentifier: assetIdentifier), approvalItem: approvalItem)
            })
        }

        return PHPickerResultsLoadResult(
            resolvablePendingAttachments: resolvablePendingAttachments,
            didAddAttachments: didAddAttachments,
        )
    }

    func picker(_ picker: PHPickerViewController, didFinishPicking results: [PHPickerResult]) {
        let loadResult = if self.pendingAttachments.contains(where: {
            return if case .camera = $0.source { true } else { false }
        }) {
            // When there are camera attachments, there isn't a straightforward
            // way to handle re-ordering selection, so we just drop the order
            loadUnorderedPHPickerResults(results)
        } else {
            loadOrderedPHPickerResults(results)
        }

        if
            !loadResult.didAddAttachments,
            viewControllers.first is PhotoCaptureViewController
        {
            picker.dismiss(animated: true)
            if self.pendingAttachments.isEmpty {
                captureViewController.captureMode = .single
            }
            captureViewController.updateDoneButtonAppearance()
            return
        }

        if loadResult.resolvablePendingAttachments.isEmpty {
            self.pendingAttachments = []
            // The user tapped the cancel button or deselected everything
            self.view.layer.opacity = 0
            self.sendMediaNavDelegate?.sendMediaNavDidCancel(self)
            return
        }

        showApprovalAfterProcessing(
            resolvablePendingAttachments: loadResult.resolvablePendingAttachments,
            pickerViewController: picker,
        )
    }
}

extension SendMediaNavigationController: UIAdaptivePresentationControllerDelegate {
    func presentationControllerDidDismiss(_ presentationController: UIPresentationController) {
        // The user swiped the photo picker down
        self.sendMediaNavDelegate?.sendMediaNavDidCancel(self)
    }
}

private extension SendMediaNavigationController {
    func showApprovalAfterProcessing(
        resolvablePendingAttachments: [() async throws -> PendingAttachment],
        pickerViewController: PHPickerViewController,
    ) {
        ModalActivityIndicatorViewController.present(
            fromViewController: pickerViewController,
            canCancel: true,
            asyncBlock: { modal in
                let result = await Result<[PendingAttachment], any Error> {
                    var pendingAttachments = [PendingAttachment]()
                    for resolvablePendingAttachment in resolvablePendingAttachments {
                        try Task.checkCancellation()
                        pendingAttachments.append(try await resolvablePendingAttachment())
                    }
                    return pendingAttachments
                }
                modal.dismissIfNotCanceled(completionIfNotCanceled: {
                    do {
                        self.pendingAttachments = try result.get()
                        self.showApprovalViewController()
                        pickerViewController.dismiss(animated: true)
                    } catch SignalAttachmentError.fileSizeTooLarge {
                        OWSActionSheets.showActionSheet(
                            title: OWSLocalizedString(
                                "ATTACHMENT_ERROR_FILE_SIZE_TOO_LARGE",
                                comment: "Attachment error message for attachments whose data exceed file size limits"
                            )
                        )
                    } catch {
                        Logger.warn("failed to prepare attachments. error: \(error)")
                        OWSActionSheets.showActionSheet(title: OWSLocalizedString("IMAGE_PICKER_FAILED_TO_PROCESS_ATTACHMENTS", comment: "alert title"))
                    }
                })
            }
        )
    }
}

extension SendMediaNavigationController: AttachmentApprovalViewControllerDelegate {

    func attachmentApproval(_ attachmentApproval: AttachmentApprovalViewController, didChangeMessageBody newMessageBody: MessageBody?) {
        sendMediaNavDelegate?.sendMediaNav(self, didChangeMessageBody: newMessageBody)
    }

    func attachmentApproval(_ attachmentApproval: AttachmentApprovalViewController, didChangeViewOnceState isViewOnce: Bool) {
        sendMediaNavDelegate?.sendMediaNav(self, didChangeViewOnceState: isViewOnce)
    }

    func attachmentApproval(_ attachmentApproval: AttachmentApprovalViewController, didRemoveAttachment attachmentApprovalItem: AttachmentApprovalItem) {
        self.pendingAttachments.removeAll(where: { $0.approvalItem.isIdenticalTo(attachmentApprovalItem) })
    }

    func attachmentApproval(
        _ attachmentApproval: AttachmentApprovalViewController,
        didApproveAttachments approvedAttachments: ApprovedAttachments,
        messageBody: MessageBody?,
    ) {
        sendMediaNavDelegate?.sendMediaNav(
            self,
            didApproveAttachments: approvedAttachments,
            messageBody: messageBody,
        )
    }

    func attachmentApprovalDidCancel() {
        sendMediaNavDelegate?.sendMediaNavDidCancel(self)
    }

    func attachmentApprovalDidTapAddMore(_ attachmentApproval: AttachmentApprovalViewController) {
        if let cameraViewController = viewControllers.first as? PhotoCaptureViewController {
            // Current design dictates we'll go "back" to the single thing before us.
            owsAssertDebug(viewControllers.count == 2)
            cameraViewController.captureMode = .multi
            popViewController(animated: true)
            return
        }

        presentAdditionalPhotosPicker()
    }

    private func presentAdditionalPhotosPicker() {
        var config = Self.phPickerConfiguration(
            cameraAttachmentCount: self.pendingAttachments.count(where: {
                switch $0.source {
                case .camera: true
                case .systemLibrary: false
                }
            }),
        )
        config.preselectedAssetIdentifiers = self.pendingAttachments.compactMap({
            switch $0.source {
            case .camera: nil
            case .systemLibrary(let systemIdentifier): systemIdentifier
            }
        })

        let vc = PHPickerViewController(configuration: config)
        vc.delegate = self
        // Intentionally do not set the presentationController delegate because
        // we don't need to do anything when the user swipes it down if showing
        // the picker for _additional_ photos.
        present(vc, animated: true)
    }
}

extension SendMediaNavigationController: AttachmentApprovalViewControllerDataSource {

    var attachmentApprovalTextInputContextIdentifier: String? {
        sendMediaNavDataSource?.sendMediaNavTextInputContextIdentifier
    }

    var attachmentApprovalRecipientNames: [String] {
        sendMediaNavDataSource?.sendMediaNavRecipientNames ?? []
    }

    func attachmentApprovalMentionableAcis(tx: DBReadTransaction) -> [Aci] {
        sendMediaNavDataSource?.sendMediaNavMentionableAcis(tx: tx) ?? []
    }

    func attachmentApprovalMentionCacheInvalidationKey() -> String {
        sendMediaNavDataSource?.sendMediaNavMentionCacheInvalidationKey() ?? UUID().uuidString
    }
}

extension SendMediaNavigationController: StickerPickerSheetDelegate {
    func makeManageStickersViewController(for stickerPickerSheet: StickerPickerSheet) -> UIViewController {
        let manageStickersView = ManageStickersViewController()
        let navigationController = OWSNavigationController(rootViewController: manageStickersView)
        return navigationController
    }
}

private struct PendingAttachment {
    var source: AttachmentSource
    var approvalItem: AttachmentApprovalItem
}

private enum AttachmentSource {
    case camera
    case systemLibrary(systemIdentifier: String)
}
