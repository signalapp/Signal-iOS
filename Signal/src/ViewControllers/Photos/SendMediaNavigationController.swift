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

    func sendMediaNav(_ sendMediaNavigationController: SendMediaNavigationController, didApproveAttachments attachments: [SignalAttachment], messageBody: MessageBody?)

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
        attachment: SignalAttachment,
        hasQuotedReplyDraft: Bool,
        delegate: SendMediaNavDelegate,
        dataSource: SendMediaNavDataSource
    ) -> SendMediaNavigationController {
        let navController = SendMediaNavigationController(hasQuotedReplyDraft: hasQuotedReplyDraft)
        navController.sendMediaNavDelegate = delegate
        navController.sendMediaNavDataSource = dataSource
        navController.modalPresentationStyle = .overCurrentContext

        let approvalItem = AttachmentApprovalItem(attachment: attachment, canSave: false)
        let libraryMedia = MediaLibraryAttachment(asset: asset, attachmentApprovalItemPromise: .value(approvalItem))
        navController.attachmentDrafts.append(.picker(attachment: libraryMedia))

        navController.showApprovalViewController(
            attachmentApprovalItems: [approvalItem]
        )

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

    // MARK: - Attachments

    private var attachmentCount: Int {
        return attachmentDrafts.count
    }

    private var attachmentDrafts: [AttachmentDraft] = []

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

    private func showApprovalViewController(
        attachmentApprovalItems: [AttachmentApprovalItem]
    ) {
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
        let approvalViewController = AttachmentApprovalViewController(options: options, attachmentApprovalItems: attachmentApprovalItems)
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
        if attachmentDrafts.count == 0 {
            self.sendMediaNavDelegate?.sendMediaNavDidCancel(self)
        } else {
            let alert = ActionSheetController()
            alert.overrideUserInterfaceStyle = .dark

            let confirmAbandonText = OWSLocalizedString("SEND_MEDIA_CONFIRM_ABANDON_ALBUM",
                                                       comment: "alert action, confirming the user wants to exit the media flow and abandon any photos they've taken")
            let confirmAbandonAction = ActionSheetAction(title: confirmAbandonText,
                                                         style: .destructive,
                                                         handler: { [weak self] _ in
                guard let self = self else { return }
                self.sendMediaNavDelegate?.sendMediaNavDidCancel(self)
            })
            alert.addAction(confirmAbandonAction)
            let dontAbandonAction = ActionSheetAction(title: dontAbandonText,
                                                      style: .default,
                                                      handler: { _ in  })
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
        guard attachmentDrafts.count > 0 else {
            owsFailDebug("No camera attachments found")
            return
        }
        showApprovalAfterProcessingAnyMediaLibrarySelections()
    }

    func photoCaptureViewController(_ photoCaptureViewController: PhotoCaptureViewController,
                                    didFinishWithTextAttachment textAttachment: UnsentTextAttachment) {
        sendMediaNavDelegate?.sendMediaNav(self, didFinishWithTextAttachment: textAttachment)
    }

    func photoCaptureViewControllerDidCancel(_ photoCaptureViewController: PhotoCaptureViewController) {
        let dontAbandonText = OWSLocalizedString("SEND_MEDIA_RETURN_TO_CAMERA", comment: "alert action when the user decides not to cancel the media flow after all.")
        didRequestExit(dontAbandonText: dontAbandonText)
    }

    func photoCaptureViewControllerViewWillAppear(_ photoCaptureViewController: PhotoCaptureViewController) {
        if photoCaptureViewController.captureMode == .single, attachmentCount == 1, case .camera = attachmentDrafts.last {
            // User is navigating back to the camera screen, indicating they want to discard the previously captured item.
            discardDraft()
        }
    }

    func photoCaptureViewControllerDidTryToCaptureTooMany(_ photoCaptureViewController: PhotoCaptureViewController) {
        showTooManySelectedToast()
    }

    func photoCaptureViewControllerCanCaptureMoreItems(_ photoCaptureViewController: PhotoCaptureViewController) -> Bool {
        return attachmentCount < SignalAttachment.maxAttachmentsAllowed
    }

    func discardDraft() {
        owsAssertDebug(attachmentDrafts.count <= 1)
        if let lastAttachmentDraft = attachmentDrafts.last {
            attachmentDrafts.removeAll { $0 == lastAttachmentDraft }
        }
        owsAssertDebug(attachmentDrafts.count == 0)
    }

    func photoCaptureViewControllerDidRequestPresentPhotoLibrary(_ photoCaptureViewController: PhotoCaptureViewController) {
        presentAdditionalPhotosPicker()
    }

    func photoCaptureViewController(_ photoCaptureViewController: PhotoCaptureViewController,
                                    didRequestSwitchCaptureModeTo captureMode: PhotoCaptureViewController.CaptureMode,
                                    completion: @escaping (Bool) -> Void) {
        // .multi always can be enabled.
        guard captureMode == .single else {
            completion(true)
            return
        }
        // Disable immediately if there's no media attachments yet.
        guard attachmentCount > 0 else {
            completion(true)
            return
        }
        // Ask to delete all existing media attachments.
        let title = OWSLocalizedString("SEND_MEDIA_TURN_OFF_MM_TITLE",
                                      comment: "In-app camera: title for the prompt to turn off multi-mode that will cause previously taken photos to be discarded.")
        let message = OWSLocalizedString("SEND_MEDIA_TURN_OFF_MM_MESSAGE",
                                        comment: "In-app camera: message for the prompt to turn off multi-mode that will cause previously taken photos to be discarded.")
        let buttonTitle = OWSLocalizedString("SEND_MEDIA_TURN_OFF_MM_BUTTON",
                                            comment: "In-app camera: confirmation button in the prompt to turn off multi-mode.")
        let actionSheet = ActionSheetController(title: title, message: message)
        actionSheet.overrideUserInterfaceStyle = .dark
        actionSheet.addAction(ActionSheetAction(title: buttonTitle, style: .destructive) { _ in
            self.attachmentDrafts.removeAll()
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
        attachmentCount
    }

    func addMedia(attachment: SignalAttachment) {
        let cameraCaptureAttachment = CameraCaptureAttachment(signalAttachment: attachment)
        attachmentDrafts.append(.camera(attachment: cameraCaptureAttachment))
    }
}

extension SendMediaNavigationController: PHPickerViewControllerDelegate {
    private struct PHPickerResultsLoadResult {
        let attachmentDrafts: [AttachmentDraft]
        let didAddAttachments: Bool
    }

    /// Load the `results` in the order they are given. Any other existing
    /// `AttachmentDraft`s will be removed from `self.attachmentDrafts`.
    private func loadOrderedPHPickerResults(
        _ results: [PHPickerResult]
    ) -> PHPickerResultsLoadResult {
        var didAddAttachments = false
        let attachmentDraftsByAssetID: [String: AttachmentDraft] = Dictionary(
            uniqueKeysWithValues: attachmentDrafts.compactMap { attachmentDraft in
                guard let systemID = attachmentDraft.systemIdentifier else {
                    return nil
                }
                return (systemID, attachmentDraft)
            }
        )

        let attachmentDrafts: [AttachmentDraft] = results.map { result in
            if
                let assetID = result.assetIdentifier,
                let existingItem = attachmentDraftsByAssetID[assetID]
            {
                return existingItem
            }

            didAddAttachments = true
            let attachment = PHPickerAttachment(
                result: result,
                attachmentApprovalItemPromise: Promise.wrapAsync {
                    let attachment = try await TypedItemProvider
                        .make(for: result.itemProvider)
                        .buildAttachment()
                    return AttachmentApprovalItem(
                        attachment: attachment,
                        canSave: false
                    )
                }
            )
            return .phPicker(attachment: attachment)
        }

        return PHPickerResultsLoadResult(
            attachmentDrafts: attachmentDrafts,
            didAddAttachments: didAddAttachments
        )
    }

    /// Load the `results` on top of the existing `AttachmentDraft`s in
    /// `self.attachmentDrafts`, adding new items to the end.
    private func loadUnorderedPHPickerResults(
        _ results: [PHPickerResult]
    ) -> PHPickerResultsLoadResult {
        var attachmentDrafts = self.attachmentDrafts
        var oldAttachments = Set(attachmentDrafts.attachmentSystemIdentifiers)
        var didAddAttachments = false
        results.filter { result in
            if let assetID = result.assetIdentifier {
                let removedItem = oldAttachments.remove(assetID)
                let alreadyIncluded = removedItem != nil
                if alreadyIncluded {
                    return false
                }
            }
            didAddAttachments = true
            return true
        }.map { result in
            PHPickerAttachment(
                result: result,
                attachmentApprovalItemPromise: Promise.wrapAsync {
                    let attachment = try await TypedItemProvider
                        .make(for: result.itemProvider)
                        .buildAttachment()
                    return AttachmentApprovalItem(
                        attachment: attachment,
                        canSave: false
                    )
                }
            )
        }.forEach { attachment in
            attachmentDrafts.append(.phPicker(attachment: attachment))
        }

        // Anything left in here was deselected
        oldAttachments.forEach { oldAttachment in
            attachmentDrafts.remove(itemWithSystemID: oldAttachment)
        }

        return PHPickerResultsLoadResult(
            attachmentDrafts: attachmentDrafts,
            didAddAttachments: didAddAttachments
        )
    }

    func picker(_ picker: PHPickerViewController, didFinishPicking results: [PHPickerResult]) {
        let loadResult = if attachmentDrafts.contains(where: {
            if case .camera = $0 { true } else { false }
        }) {
            // When there are camera attachments, there isn't a straightforward
            // way to handle re-ordering selection, so we just drop the order
            loadUnorderedPHPickerResults(results)
        } else {
            loadOrderedPHPickerResults(results)
        }

        self.attachmentDrafts = loadResult.attachmentDrafts

        if
            !loadResult.didAddAttachments,
            viewControllers.first is PhotoCaptureViewController
        {
            picker.dismiss(animated: true)
            if attachmentCount <= 0 {
                captureViewController.captureMode = .single
            }
            captureViewController.updateDoneButtonAppearance()
            return
        }

        if attachmentCount <= 0 {
            // The user tapped the cancel button or deselected everything
            self.view.layer.opacity = 0
            self.sendMediaNavDelegate?.sendMediaNavDidCancel(self)
            return
        }

        showApprovalAfterProcessingAnyMediaLibrarySelections(picker: picker)
    }
}

extension SendMediaNavigationController: UIAdaptivePresentationControllerDelegate {
    func presentationControllerDidDismiss(_ presentationController: UIPresentationController) {
        // The user swiped the photo picker down
        self.sendMediaNavDelegate?.sendMediaNavDidCancel(self)
    }
}

extension SendMediaNavigationController {
    func showApprovalAfterProcessingAnyMediaLibrarySelections(
        picker: PHPickerViewController? = nil
    ) {
        ModalActivityIndicatorViewController.present(
            fromViewController: picker ?? self,
            canCancel: true,
            asyncBlock: { modal in
                let result = await Result<[AttachmentApprovalItem], any Error> {
                    var attachmentApprovalItems = [AttachmentApprovalItem]()
                    for attachmentApprovalItemPromise in self.attachmentDrafts.map(\.attachmentApprovalItemPromise) {
                        try Task.checkCancellation()
                        attachmentApprovalItems.append(try await attachmentApprovalItemPromise.awaitable())
                    }
                    return attachmentApprovalItems
                }
                modal.dismissIfNotCanceled(completionIfNotCanceled: {
                    do {
                        let attachmentApprovalItems = try result.get()
                        self.showApprovalViewController(attachmentApprovalItems: attachmentApprovalItems)
                        picker?.dismiss(animated: true)
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

    func attachmentApproval(_ attachmentApproval: AttachmentApprovalViewController, didRemoveAttachment attachment: SignalAttachment) {
        guard let removedDraft = attachmentDrafts.attachmentDraft(for: attachment) else {
            owsFailDebug("removedDraft was unexpectedly nil")
            return
        }

        attachmentDrafts.removeAll { $0 == removedDraft }
    }

    func attachmentApproval(_ attachmentApproval: AttachmentApprovalViewController, didApproveAttachments attachments: [SignalAttachment], messageBody: MessageBody?) {
        sendMediaNavDelegate?.sendMediaNav(self, didApproveAttachments: attachments, messageBody: messageBody)
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
            cameraAttachmentCount: attachmentDrafts.cameraAttachmentCount
        )
        config.preselectedAssetIdentifiers = attachmentDrafts.attachmentSystemIdentifiers

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
    func makeManageStickersViewController() -> UIViewController {
        let manageStickersView = ManageStickersViewController()
        let navigationController = OWSNavigationController(rootViewController: manageStickersView)
        return navigationController
    }
}

private enum AttachmentDraft: Equatable {

    case camera(attachment: CameraCaptureAttachment)

    case picker(attachment: MediaLibraryAttachment)

    case phPicker(attachment: PHPickerAttachment)
}

private extension AttachmentDraft {
    var attachmentApprovalItemPromise: Promise<AttachmentApprovalItem> {
        switch self {
        case .camera(let cameraAttachment):
            return cameraAttachment.attachmentApprovalItemPromise
        case .picker(let pickerAttachment):
            return pickerAttachment.attachmentApprovalItemPromise
        case .phPicker(let phPickerAttachment):
            return phPickerAttachment.attachmentApprovalItemPromise
        }
    }

    var systemIdentifier: String? {
        switch self {
        case .picker(let attachment):
            attachment.asset.localIdentifier
        case .camera:
            nil
        case .phPicker(let phPickerAttachment):
            phPickerAttachment.result.assetIdentifier
        }
    }
}

// MARK: - AttachmentDrafts

private extension Array where Element == AttachmentDraft {
    var cameraAttachmentCount: Int {
        count { attachmentDraft in
            switch attachmentDraft {
            case .camera: true
            case .picker, .phPicker: false
            }
        }
    }

    var attachmentSystemIdentifiers: [String] {
        compactMap { attachmentDraft in
            attachmentDraft.systemIdentifier
        }
    }

    mutating func remove(itemWithSystemID id: String) {
        self.removeAll { item in
            switch item {
            case .camera:
                false
            case .picker(let attachment):
                attachment.asset.localIdentifier == id
            case .phPicker(let attachment):
                attachment.result.assetIdentifier == id
            }
        }
    }

    func attachmentDraft(for attachment: SignalAttachment) -> AttachmentDraft? {
        self.first { attachmentDraft in
            guard let attachmentApprovalItem = attachmentDraft.attachmentApprovalItemPromise.value else {
                // method should only be used after draft promises have been resolved.
                owsFailDebug("attachment was unexpectedly nil")
                return false
            }
            return attachmentApprovalItem.attachment == attachment
        }
    }
}

// MARK: - CameraCaptureAttachment

private struct CameraCaptureAttachment: Hashable, Equatable {

    let signalAttachment: SignalAttachment
    let attachmentApprovalItem: AttachmentApprovalItem
    let attachmentApprovalItemPromise: Promise<AttachmentApprovalItem>

    init(signalAttachment: SignalAttachment) {
        self.signalAttachment = signalAttachment
        self.attachmentApprovalItem = AttachmentApprovalItem(attachment: signalAttachment, canSave: true)
        self.attachmentApprovalItemPromise = Promise.value(attachmentApprovalItem)
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(signalAttachment)
    }

    static func == (lhs: CameraCaptureAttachment, rhs: CameraCaptureAttachment) -> Bool {
        return lhs.signalAttachment == rhs.signalAttachment
    }
}

private struct MediaLibraryAttachment: Hashable, Equatable {

    let asset: PHAsset
    let attachmentApprovalItemPromise: Promise<AttachmentApprovalItem>

    func hash(into hasher: inout Hasher) {
        hasher.combine(asset)
    }

    static func == (lhs: MediaLibraryAttachment, rhs: MediaLibraryAttachment) -> Bool {
        return lhs.asset == rhs.asset
    }
}

private struct PHPickerAttachment: Hashable {
    let result: PHPickerResult
    let attachmentApprovalItemPromise: Promise<AttachmentApprovalItem>

    init(result: PHPickerResult, attachmentApprovalItemPromise: Promise<AttachmentApprovalItem>) {
        self.result = result
        self.attachmentApprovalItemPromise = attachmentApprovalItemPromise
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(result)
    }

    static func == (lhs: PHPickerAttachment, rhs: PHPickerAttachment) -> Bool {
        return lhs.result == rhs.result
    }
}
