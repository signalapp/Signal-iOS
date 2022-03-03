//
//  Copyright (c) 2022 Open Whisper Systems. All rights reserved.
//

import Foundation
import Photos
import SignalUI

@objc
protocol SendMediaNavDelegate: AnyObject {
    func sendMediaNavDidCancel(_ sendMediaNavigationController: SendMediaNavigationController)
    func sendMediaNav(_ sendMediaNavigationController: SendMediaNavigationController, didApproveAttachments attachments: [SignalAttachment], messageBody: MessageBody?)

    func sendMediaNavInitialMessageBody(_ sendMediaNavigationController: SendMediaNavigationController) -> MessageBody?
    func sendMediaNav(_ sendMediaNavigationController: SendMediaNavigationController, didChangeMessageBody newMessageBody: MessageBody?)
    var sendMediaNavApprovalButtonImageName: String { get }
    var sendMediaNavCanSaveAttachments: Bool { get }
    var sendMediaNavTextInputContextIdentifier: String? { get }
    var sendMediaNavRecipientNames: [String] { get }
    var sendMediaNavMentionableAddresses: [SignalServiceAddress] { get }
}

@objc
class CameraFirstCaptureNavigationController: SendMediaNavigationController {

    @objc
    private(set) var cameraFirstCaptureSendFlow: CameraFirstCaptureSendFlow!

    @objc
    public class func cameraFirstModal() -> CameraFirstCaptureNavigationController {
        let navController = CameraFirstCaptureNavigationController()
        navController.setViewControllers([navController.captureViewController], animated: false)

        let cameraFirstCaptureSendFlow = CameraFirstCaptureSendFlow()
        navController.cameraFirstCaptureSendFlow = cameraFirstCaptureSendFlow
        navController.sendMediaNavDelegate = cameraFirstCaptureSendFlow

        return navController
    }
}

@objc
class SendMediaNavigationController: OWSNavigationController {

    var attachmentCount: Int {
        return attachmentDraftCollection.count
    }

    // MARK: - Overrides

    override var prefersStatusBarHidden: Bool {
        guard !CurrentAppContext().hasActiveCall else {
            return false
        }
        return true
    }

    override var preferredStatusBarStyle: UIStatusBarStyle {
        if topViewController is ConversationPickerViewController {
            return .default
        }
        return  .lightContent
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        self.delegate = self
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        DispatchQueue.main.async {
            // Pre-layout views for snappier response should the user decide to switch.

            if PHPhotoLibrary.authorizationStatus() == .authorized {
                self.mediaLibraryViewController.view.layoutIfNeeded()
            }

            if AVCaptureDevice.authorizationStatus(for: .video) == .authorized {
                self.captureViewController.view.layoutIfNeeded()
            }
        }
    }

    // MARK: -

    @objc
    public weak var sendMediaNavDelegate: SendMediaNavDelegate?

    @objc
    public class func showingCameraFirst() -> SendMediaNavigationController {
        let navController = SendMediaNavigationController()
        navController.setViewControllers([navController.captureViewController], animated: false)
        return navController
    }

    @objc
    public class func showingMediaLibraryFirst() -> SendMediaNavigationController {
        let navController = SendMediaNavigationController()
        navController.setViewControllers([navController.mediaLibraryViewController], animated: false)
        return navController
    }

    @objc(showingApprovalWithPickedLibraryMediaAsset:attachment:delegate:)
    public class func showingApprovalWithPickedLibraryMedia(asset: PHAsset,
                                                            attachment: SignalAttachment,
                                                            delegate: SendMediaNavDelegate) -> SendMediaNavigationController {
        let navController = SendMediaNavigationController()
        navController.sendMediaNavDelegate = delegate

        let approvalItem = AttachmentApprovalItem(attachment: attachment, canSave: false)
        let libraryMedia = MediaLibraryAttachment(asset: asset,
                                                  attachmentApprovalItemPromise: .value(approvalItem))
        navController.attachmentDraftCollection.append(.picker(attachment: libraryMedia))

        navController.setViewControllers([navController.mediaLibraryViewController], animated: false)

        // Since we're starting on the approval view, include cancel to allow the user to immediately dismiss.
        // If they choose to add more, `hasCancel` will go away and they'll enter the normal gallery flow.
        navController.pushApprovalViewController(
            attachmentApprovalItems: [approvalItem],
            options: [.canAddMore, .hasCancel],
            animated: false
        )

        return navController
    }

    func fadeTo(viewControllers: [UIViewController], duration: CFTimeInterval) {
        AssertIsOnMainThread()

        let transition: CATransition = CATransition()
        transition.duration = duration
        transition.type = CATransitionType.fade
        view.layer.add(transition, forKey: nil)
        setViewControllers(viewControllers, animated: false)
    }

    // MARK: State

    private var attachmentDraftCollection: AttachmentDraftCollection = .empty

    private var attachmentApprovalItemPromises: [Promise<AttachmentApprovalItem>] {
        return attachmentDraftCollection.attachmentApprovalItemPromises
    }

    // MARK: Child VC's

    fileprivate lazy var captureViewController: PhotoCaptureViewController = {
        let viewController = PhotoCaptureViewController()
        viewController.delegate = self
        viewController.dataSource = self
        return viewController
    }()

    private lazy var mediaLibraryViewController: ImagePickerGridController = {
        let viewController = ImagePickerGridController()
        viewController.delegate = self
        viewController.dataSource = self
        return viewController
    }()

    private func pushApprovalViewController(attachmentApprovalItems: [AttachmentApprovalItem],
                                            options: AttachmentApprovalViewControllerOptions = .canAddMore,
                                            animated: Bool) {
        guard let sendMediaNavDelegate = self.sendMediaNavDelegate else {
            owsFailDebug("sendMediaNavDelegate was unexpectedly nil")
            return
        }

        let approvalViewController = AttachmentApprovalViewController(options: options,
                                                                      sendButtonImageName: sendMediaNavDelegate.sendMediaNavApprovalButtonImageName,
                                                                      attachmentApprovalItems: attachmentApprovalItems)
        approvalViewController.approvalDelegate = self
        approvalViewController.messageBody = sendMediaNavDelegate.sendMediaNavInitialMessageBody(self)

        if animated {
            fadeTo(viewControllers: viewControllers + [approvalViewController], duration: 0.3)
        } else {
            pushViewController(approvalViewController, animated: false)
        }
    }

    private func didRequestExit(dontAbandonText: String) {
        if attachmentDraftCollection.count == 0 {
            self.sendMediaNavDelegate?.sendMediaNavDidCancel(self)
        } else {
            let alert = ActionSheetController(title: nil, message: nil)

            let confirmAbandonText = NSLocalizedString("SEND_MEDIA_CONFIRM_ABANDON_ALBUM",
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

extension SendMediaNavigationController: UINavigationControllerDelegate {

    func navigationController(_ navigationController: UINavigationController, willShow viewController: UIViewController, animated: Bool) {
        updateNavbarTheme(for: viewController, animated: animated)
    }

    // In case back navigation was canceled, we re-apply whatever is showing.
    func navigationController(_ navigationController: UINavigationController, didShow viewController: UIViewController, animated: Bool) {
        updateNavbarTheme(for: viewController, animated: animated)
    }

    func navigationControllerSupportedInterfaceOrientations(_ navigationController: UINavigationController) -> UIInterfaceOrientationMask {
        return navigationController.topViewController?.supportedInterfaceOrientations ?? UIDevice.current.defaultSupportedOrientations
    }

    // MARK: - Helpers

    private func updateNavbarTheme(for viewController: UIViewController, animated: Bool) {
        let showNavbar: (OWSNavigationBar.NavigationBarStyle) -> Void = { navigationBarStyle in
            if self.isNavigationBarHidden {
                self.setNavigationBarHidden(false, animated: animated)
            }
            guard let owsNavBar = self.navigationBar as? OWSNavigationBar else {
                owsFailDebug("unexpected navigationBar: \(self.navigationBar)")
                return
            }
            owsNavBar.switchToStyle(navigationBarStyle)
        }

        switch viewController {
        case is PhotoCaptureViewController:
            if !isNavigationBarHidden {
                setNavigationBarHidden(true, animated: animated)
            }
        case is AttachmentApprovalViewController:
            showNavbar(.alwaysDarkAndClear)
        case is ImagePickerGridController:
            showNavbar(.alwaysDarkAndClear)
        case is ConversationPickerViewController:
            showNavbar(.default)
        default:
            owsFailDebug("unexpected viewController: \(viewController)")
            return
        }
    }

    // MARK: - Too Many

    func showTooManySelectedToast() {
        let toastFormat = NSLocalizedString("IMAGE_PICKER_CAN_SELECT_NO_MORE_TOAST_FORMAT",
                                            comment: "Momentarily shown to the user when attempting to select more images than is allowed. Embeds {{max number of items}} that can be shared.")

        let toastText = String(format: toastFormat, NSNumber(value: SignalAttachment.maxAttachmentsAllowed))
        let toastController = ToastController(text: toastText)
        toastController.presentToastView(fromBottomOfView: view, inset: view.layoutMargins.bottom + 10)
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

    func photoCaptureViewControllerDidCancel(_ photoCaptureViewController: PhotoCaptureViewController) {
        let dontAbandonText = NSLocalizedString("SEND_MEDIA_RETURN_TO_CAMERA", comment: "alert action when the user decides not to cancel the media flow after all.")
        didRequestExit(dontAbandonText: dontAbandonText)
    }

    func photoCaptureViewControllerViewWillAppear(_ photoCaptureViewController: PhotoCaptureViewController) {
        if !photoCaptureViewController.isInBatchMode, attachmentCount == 1, case .camera(_) = attachmentDraftCollection.attachmentDrafts.last {
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
        self.ows_askForMediaLibraryPermissions { isGranted in
            guard isGranted else { return }

            BenchEventStart(title: "Show-Media-Library", eventId: "Show-Media-Library")
            let presentedViewController = OWSNavigationController(rootViewController: self.mediaLibraryViewController)
            if let owsNavBar = presentedViewController.navigationBar as? OWSNavigationBar {
                owsNavBar.switchToStyle(.alwaysDarkAndClear)
            }
            self.presentFullScreen(presentedViewController, animated: true)
        }
    }

    func photoCaptureViewController(_ photoCaptureViewController: PhotoCaptureViewController, didRequestSwitchBatchMode batchMode: Bool) -> Bool {
        if batchMode {
            // Always can be enabled
            return true
        }
        // Can only be disabled if there's no media attachments yet.
        return attachmentCount > 0
    }
}

extension SendMediaNavigationController: PhotoCaptureViewControllerDataSource {

    var numberOfMediaItems: Int {
        attachmentCount
    }

    func addMedia(attachment: SignalAttachment) {
        guard let sendMediaNavDelegate = self.sendMediaNavDelegate else { return }
        let cameraCaptureAttachment = CameraCaptureAttachment(signalAttachment: attachment, canSave: sendMediaNavDelegate.sendMediaNavCanSaveAttachments)
        attachmentDraftCollection.append(.camera(attachment: cameraCaptureAttachment))
    }
}

extension SendMediaNavigationController: ImagePickerGridControllerDelegate {

    func imagePickerDidRequestSendMedia(_ imagePicker: ImagePickerGridController) {
        if let navigationController = presentedViewController as? OWSNavigationController,
           navigationController.viewControllers.contains(imagePicker) {
            dismiss(animated: true) {
                self.showApprovalAfterProcessingAnyMediaLibrarySelections()
            }
            return
        }
        showApprovalAfterProcessingAnyMediaLibrarySelections()
    }

    func imagePickerDidCancel(_ imagePicker: ImagePickerGridController) {
        if let navigationController = presentedViewController as? OWSNavigationController,
           navigationController.viewControllers.contains(imagePicker) {
            dismiss(animated: true)
            return
        }

        let dontAbandonText = NSLocalizedString("SEND_MEDIA_RETURN_TO_MEDIA_LIBRARY", comment: "alert action when the user decides not to cancel the media flow after all.")
        didRequestExit(dontAbandonText: dontAbandonText)
    }

    func showApprovalAfterProcessingAnyMediaLibrarySelections() {
        let backgroundBlock: (ModalActivityIndicatorViewController) -> Void = { modal in
            let approvalItemsPromise: Promise<[AttachmentApprovalItem]> = Promise.when(fulfilled: self.attachmentDraftCollection.attachmentApprovalItemPromises)
            firstly { () -> Promise<Swift.Result<[AttachmentApprovalItem], Error>> in
                return Promise.race(
                    approvalItemsPromise.map { attachmentApprovalItems -> Swift.Result<[AttachmentApprovalItem], Error> in
                        Swift.Result.success(attachmentApprovalItems)
                    },
                    modal.wasCancelledPromise.map { _ -> Swift.Result<[AttachmentApprovalItem], Error> in
                        Swift.Result.failure(OWSGenericError("Modal was cancelled."))
                    })
            }.map { (result: Swift.Result<[AttachmentApprovalItem], Error>) in
                modal.dismiss {
                    switch result {
                    case .success(let attachmentApprovalItems):
                        Logger.debug("built all attachments")
                        self.pushApprovalViewController(attachmentApprovalItems: attachmentApprovalItems, animated: true)
                    case .failure:
                        // Do nothing.
                        break
                    }
                }
            }.catch { error in
                Logger.error("failed to prepare attachments. error: \(error)")
                modal.dismiss {
                    OWSActionSheets.showActionSheet(title: NSLocalizedString("IMAGE_PICKER_FAILED_TO_PROCESS_ATTACHMENTS", comment: "alert title"))
                }
            }
        }

        ModalActivityIndicatorViewController.present(fromViewController: self,
                                                     canCancel: true,
                                                     backgroundBlock: backgroundBlock)
    }

    func imagePicker(_ imagePicker: ImagePickerGridController, didSelectAsset asset: PHAsset, attachmentPromise: Promise<SignalAttachment>) {
        guard let sendMediaNavDelegate = sendMediaNavDelegate else { return }
        guard !attachmentDraftCollection.hasPickerAttachment(forAsset: asset) else { return }

        let attachmentApprovalItemPromise = attachmentPromise.map { attachment in
            AttachmentApprovalItem(attachment: attachment,
                                   canSave: sendMediaNavDelegate.sendMediaNavCanSaveAttachments)
        }

        let libraryMedia = MediaLibraryAttachment(asset: asset, attachmentApprovalItemPromise: attachmentApprovalItemPromise)
        attachmentDraftCollection.append(.picker(attachment: libraryMedia))
    }

    func imagePicker(_ imagePicker: ImagePickerGridController, didDeselectAsset asset: PHAsset) {
        guard let draft = attachmentDraftCollection.pickerAttachment(forAsset: asset) else {
            return
        }
        attachmentDraftCollection.remove(.picker(attachment: draft))
    }

    func imagePickerDidTryToSelectTooMany(_ imagePicker: ImagePickerGridController) {
        showTooManySelectedToast()
    }
}

extension SendMediaNavigationController: ImagePickerGridControllerDataSource {

    func imagePicker(_ imagePicker: ImagePickerGridController, isAssetSelected asset: PHAsset) -> Bool {
        return attachmentDraftCollection.hasPickerAttachment(forAsset: asset)
    }

    func imagePickerCanSelectMoreItems(_ imagePicker: ImagePickerGridController) -> Bool {
        return attachmentCount < SignalAttachment.maxAttachmentsAllowed
    }

}

extension SendMediaNavigationController: AttachmentApprovalViewControllerDelegate {

    func attachmentApprovalDidAppear(_ attachmentApproval: AttachmentApprovalViewController) {
    }

    func attachmentApproval(_ attachmentApproval: AttachmentApprovalViewController, didChangeMessageBody newMessageBody: MessageBody?) {
        sendMediaNavDelegate?.sendMediaNav(self, didChangeMessageBody: newMessageBody)
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
        // Current design dicates we'll go "back" to the single thing before us.
        owsAssertDebug(viewControllers.count == 2)

        if let cameraViewController = viewControllers.first as? PhotoCaptureViewController {
            cameraViewController.switchToBatchMode()
        }

        popViewController(animated: true)
    }

    var attachmentApprovalTextInputContextIdentifier: String? {
        return sendMediaNavDelegate?.sendMediaNavTextInputContextIdentifier
    }

    var attachmentApprovalRecipientNames: [String] {
        return sendMediaNavDelegate?.sendMediaNavRecipientNames ?? []
    }

    var attachmentApprovalMentionableAddresses: [SignalServiceAddress] {
        return sendMediaNavDelegate?.sendMediaNavMentionableAddresses ?? []
    }
}

private enum AttachmentDraft {
    case camera(attachment: CameraCaptureAttachment)
    case picker(attachment: MediaLibraryAttachment)
}

private extension AttachmentDraft {
    var attachmentApprovalItemPromise: Promise<AttachmentApprovalItem> {
        switch self {
        case .camera(let cameraAttachment):
            return cameraAttachment.attachmentApprovalItemPromise
        case .picker(let pickerAttachment):
            return pickerAttachment.attachmentApprovalItemPromise
        }
    }

    var source: AttachmentDraft {
        return self
    }
}

extension AttachmentDraft: Equatable { }

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
            switch attachmentDraft.source {
            case .picker(let pickerAttachment):
                return pickerAttachment
            case .camera:
                return nil
            }
        }
    }

    var cameraAttachments: [CameraCaptureAttachment] {
        return attachmentDrafts.compactMap { attachmentDraft in
            switch attachmentDraft.source {
            case .picker:
                return nil
            case .camera(let cameraAttachment):
                return cameraAttachment
            }
        }
    }

    mutating func append(_ element: AttachmentDraft) {
        attachmentDrafts.append(element)
    }

    mutating func remove(_ element: AttachmentDraft) {
        attachmentDrafts.removeAll { $0 == element }
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

    init(signalAttachment: SignalAttachment, canSave: Bool) {
        self.signalAttachment = signalAttachment
        self.attachmentApprovalItem = AttachmentApprovalItem(attachment: signalAttachment, canSave: canSave)
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
