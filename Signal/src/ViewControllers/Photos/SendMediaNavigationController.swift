//
// Copyright 2019 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Photos
import SignalServiceKit
import SignalUI
import PhotosUI

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

    func sendMediaNavMentionableAddresses(tx: DBReadTransaction) -> [SignalServiceAddress]

    func sendMediaNavMentionCacheInvalidationKey() -> String
}

class CameraFirstCaptureNavigationController: SendMediaNavigationController {

    override var requiresContactPickerToProceed: Bool {
        true
    }

    override var canSendToStories: Bool { StoryManager.areStoriesEnabled }

    private var cameraFirstCaptureSendFlow: CameraFirstCaptureSendFlow!

    class func cameraFirstModal(storiesOnly: Bool = false, delegate: CameraFirstCaptureDelegate) -> CameraFirstCaptureNavigationController {
        let navController = CameraFirstCaptureNavigationController()
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

    // MARK: - Overrides

    override var childForStatusBarStyle: UIViewController? {
        topViewController
    }

    // MARK: -

    weak var sendMediaNavDelegate: SendMediaNavDelegate?
    weak var sendMediaNavDataSource: SendMediaNavDataSource?

    class func showingCameraFirst() -> SendMediaNavigationController {
        let navController = SendMediaNavigationController()
        navController.setViewControllers([navController.captureViewController], animated: false)
        return navController
    }

    fileprivate var nativePickerToPresent: PHPickerViewController?

    class func showingNativePicker() -> SendMediaNavigationController {
        // We want to present the photo picker in a sheet and then have the
        // editor appear behind it after you select photos, so present this
        // navigation controller as transparent with an empty view, then when
        // you select photos, `showApprovalViewController` will make it appear
        // behind the dismissing sheet and transition to the editor.
        let navController = SendMediaNavigationController(rootViewController: UIViewController())
        navController.view.layer.opacity = 0
        navController.modalPresentationStyle = .overCurrentContext

        var config = PHPickerConfiguration(photoLibrary: .shared())
        config.preferredAssetRepresentationMode = .current
        config.selectionLimit = SignalAttachment.maxAttachmentsAllowed
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
        options: AttachmentApprovalViewControllerOptions = .init(),
        delegate: SendMediaNavDelegate,
        dataSource: SendMediaNavDataSource
    ) -> SendMediaNavigationController {
        let navController = SendMediaNavigationController()
        navController.sendMediaNavDelegate = delegate
        navController.sendMediaNavDataSource = dataSource
        navController.modalPresentationStyle = .overCurrentContext

        let approvalItem = AttachmentApprovalItem(attachment: attachment, canSave: false)
        let libraryMedia = MediaLibraryAttachment(asset: asset,
                                                  attachmentApprovalItemPromise: .value(approvalItem))
        navController.attachmentDraftCollection.append(.picker(attachment: libraryMedia))

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
        return attachmentDraftCollection.count
    }

    private var attachmentDraftCollection: AttachmentDraftCollection = .empty

    private var attachmentApprovalItemPromises: [Promise<AttachmentApprovalItem>] {
        return attachmentDraftCollection.attachmentApprovalItemPromises
    }

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

    private enum ApprovalPushStyle {
        case fade
        case replace
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
        if attachmentDraftCollection.count == 0 {
            self.sendMediaNavDelegate?.sendMediaNavDidCancel(self)
        } else {
            let alert = ActionSheetController(title: nil, message: nil, theme: .translucentDark)

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
        guard attachmentDraftCollection.count > 0 else {
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
        if photoCaptureViewController.captureMode == .single, attachmentCount == 1, case .camera = attachmentDraftCollection.attachmentDrafts.last {
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
        owsAssertDebug(attachmentDraftCollection.attachmentDrafts.count <= 1)
        if let lastAttachmentDraft = attachmentDraftCollection.attachmentDrafts.last {
            attachmentDraftCollection.remove(lastAttachmentDraft)
        }
        owsAssertDebug(attachmentDraftCollection.attachmentDrafts.count == 0)
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
        let actionSheet = ActionSheetController(title: title, message: message, theme: .translucentDark)
        actionSheet.addAction(ActionSheetAction(title: buttonTitle, style: .destructive) { _ in
            self.attachmentDraftCollection.removeAll()
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
        attachmentDraftCollection.append(.camera(attachment: cameraCaptureAttachment))
    }
}

extension SendMediaNavigationController: PHPickerViewControllerDelegate {
    func picker(_ picker: PHPickerViewController, didFinishPicking results: [PHPickerResult]) {
        var oldAttachments = Set(attachmentDraftCollection.attachmentSystemIdentifiers)

        var attachmentsWereAdded = false

        results.filter { result in
            if let assetID = result.assetIdentifier {
                let removedItem = oldAttachments.remove(assetID)
                let alreadyIncluded = removedItem != nil
                if alreadyIncluded {
                    return false
                }
            }
            attachmentsWereAdded = true
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
            attachmentDraftCollection.append(.phPicker(attachment: attachment))
        }

        // Anything left in here was deselected
        oldAttachments.forEach { oldAttachment in
            attachmentDraftCollection.remove(itemWithSystemID: oldAttachment)
        }

        if !attachmentsWereAdded, viewControllers.first is PhotoCaptureViewController {
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
            picker.dismiss(animated: true) {
                self.dismiss(animated: false)
            }
            return
        }

        showApprovalAfterProcessingAnyMediaLibrarySelections(picker: picker)
    }
}

extension SendMediaNavigationController: UIAdaptivePresentationControllerDelegate {
    func presentationControllerDidDismiss(_ presentationController: UIPresentationController) {
        // The user swiped the photo picker down
        self.dismiss(animated: false)
    }
}

extension SendMediaNavigationController {
    func showApprovalAfterProcessingAnyMediaLibrarySelections(
        picker: PHPickerViewController? = nil
    ) {
        let backgroundBlock: (ModalActivityIndicatorViewController) -> Void = { modal in
            let approvalItemsPromise: Promise<[AttachmentApprovalItem]> = Promise.when(fulfilled: self.attachmentDraftCollection.attachmentApprovalItemPromises)
            firstly { () -> Promise<Result<[AttachmentApprovalItem], Error>> in
                return Promise.race(
                    approvalItemsPromise.map { attachmentApprovalItems -> Result<[AttachmentApprovalItem], Error> in
                        .success(attachmentApprovalItems)
                    },
                    modal.wasCancelledPromise.map { _ -> Result<[AttachmentApprovalItem], Error> in
                        .failure(OWSGenericError("Modal was cancelled."))
                    })
            }.map { (result: Result<[AttachmentApprovalItem], Error>) in
                modal.dismiss {
                    switch result {
                    case .success(let attachmentApprovalItems):
                        Logger.debug("built all attachments")

                        for item in attachmentApprovalItems {
                            switch item.attachment.error {
                            case nil:
                                continue
                            case .fileSizeTooLarge:
                                OWSActionSheets.showActionSheet(
                                    title: OWSLocalizedString(
                                        "ATTACHMENT_ERROR_FILE_SIZE_TOO_LARGE",
                                        comment: "Attachment error message for attachments whose data exceed file size limits"
                                    )
                                )
                                return
                            default:
                                OWSActionSheets.showActionSheet(title: OWSLocalizedString("IMAGE_PICKER_FAILED_TO_PROCESS_ATTACHMENTS", comment: "alert title"))
                                return
                            }
                        }

                        self.showApprovalViewController(attachmentApprovalItems: attachmentApprovalItems)
                        picker?.dismiss(animated: true)
                    case .failure:
                        // Do nothing.
                        break
                    }
                }
            }.catch { error in
                Logger.error("failed to prepare attachments. error: \(error)")
                modal.dismiss {
                    OWSActionSheets.showActionSheet(title: OWSLocalizedString("IMAGE_PICKER_FAILED_TO_PROCESS_ATTACHMENTS", comment: "alert title"))
                }
            }
        }

        ModalActivityIndicatorViewController.present(
            fromViewController: picker ?? self,
            canCancel: true,
            backgroundBlock: backgroundBlock
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
        guard let removedDraft = attachmentDraftCollection.attachmentDraft(forAttachment: attachment) else {
            owsFailDebug("removedDraft was unexpectedly nil")
            return
        }

        attachmentDraftCollection.remove(removedDraft)
    }

    func attachmentApproval(_ attachmentApproval: AttachmentApprovalViewController, didApproveAttachments attachments: [SignalAttachment], messageBody: MessageBody?) {
        sendMediaNavDelegate?.sendMediaNav(self, didApproveAttachments: attachments, messageBody: messageBody)
    }

    func attachmentApprovalDidCancel(_ attachmentApproval: AttachmentApprovalViewController) {
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
        var config = PHPickerConfiguration(photoLibrary: .shared())
        let photoCount = attachmentDraftCollection.cameraAttachmentCount
        config.selectionLimit = SignalAttachment.maxAttachmentsAllowed - photoCount
        config.preferredAssetRepresentationMode = .current
        config.preselectedAssetIdentifiers = attachmentDraftCollection.attachmentSystemIdentifiers

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

    func attachmentApprovalMentionableAddresses(tx: DBReadTransaction) -> [SignalServiceAddress] {
        sendMediaNavDataSource?.sendMediaNavMentionableAddresses(tx: tx) ?? []
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
}

private struct AttachmentDraftCollection {

    private(set) var attachmentDrafts: [AttachmentDraft]

    static var empty: AttachmentDraftCollection {
        return AttachmentDraftCollection(attachmentDrafts: [])
    }

    // MARK: -

    var count: Int {
        return attachmentDrafts.count
    }

    var attachmentApprovalItemPromises: [Promise<AttachmentApprovalItem>] {
        return attachmentDrafts.map { $0.attachmentApprovalItemPromise }
    }

    var pickerAttachments: [MediaLibraryAttachment] {
        return attachmentDrafts.compactMap { attachmentDraft in
            switch attachmentDraft {
            case .picker(let pickerAttachment):
                return pickerAttachment
            case .camera, .phPicker:
                return nil
            }
        }
    }

    var cameraAttachmentCount: Int {
        attachmentDrafts.count { attachmentDraft in
            switch attachmentDraft {
            case .camera: true
            case .picker, .phPicker: false
            }
        }
    }

    var attachmentSystemIdentifiers: [String] {
        return attachmentDrafts.compactMap { attachmentDraft in
            switch attachmentDraft {
            case .picker(let attachment):
                attachment.asset.localIdentifier
            case .camera:
                nil
            case .phPicker(let phPickerAttachment):
                phPickerAttachment.result.assetIdentifier
            }
        }
    }

    mutating func append(_ element: AttachmentDraft) {
        attachmentDrafts.append(element)
    }

    mutating func remove(_ element: AttachmentDraft) {
        attachmentDrafts.removeAll { $0 == element }
    }

    mutating func remove(itemWithSystemID id: String) {
        attachmentDrafts.removeAll { item in
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

    mutating func removeAll() {
        attachmentDrafts.removeAll()
    }

    func attachmentDraft(forAttachment: SignalAttachment) -> AttachmentDraft? {
        for attachmentDraft in attachmentDrafts {
            guard let attachmentApprovalItem = attachmentDraft.attachmentApprovalItemPromise.value else {
                // method should only be used after draft promises have been resolved.
                owsFailDebug("attachment was unexpectedly nil")
                continue
            }
            if attachmentApprovalItem.attachment == forAttachment {
                return attachmentDraft
            }
        }
        return nil
    }

    func pickerAttachment(forAsset asset: PHAsset) -> MediaLibraryAttachment? {
        return pickerAttachments.first { $0.asset == asset }
    }

    func hasPickerAttachment(forAsset asset: PHAsset) -> Bool {
        return pickerAttachment(forAsset: asset) != nil
    }
}

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
