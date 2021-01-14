//
//  Copyright (c) 2021 Open Whisper Systems. All rights reserved.
//

import Foundation
import Photos
import PromiseKit

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

public let fixedBottomSafeAreaInset: CGFloat = 20
public let fixedHorizontalMargin: CGFloat = 16

@objc
class SendMediaNavigationController: OWSNavigationController {
    static var bottomButtonsCenterOffset: CGFloat {
        if UIDevice.current.hasIPhoneXNotch {
            // we pin to a constant rather than margin, because on notched devices the
            // safeAreaInsets/margins change as the device rotates *EVEN THOUGH* the interface
            // is locked to portrait.
            return -1 * (CaptureButton.recordingDiameter / 2 + 4) - fixedBottomSafeAreaInset
        } else {
            return -1 * (CaptureButton.recordingDiameter / 2 + 4)
        }
    }

    static var trailingButtonsOffset: CGFloat = -28

    var attachmentCount: Int {
        return attachmentDraftCollection.count
    }

    // MARK: - Overrides

    override var prefersStatusBarHidden: Bool {
        guard !OWSWindowManager.shared.hasCall else {
            return false
        }

        return true
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        self.delegate = self

        let bottomButtonsCenterOffset = SendMediaNavigationController.bottomButtonsCenterOffset

        view.addSubview(batchModeButton)
        batchModeButton.setCompressionResistanceHigh()

        view.addSubview(doneButton)
        doneButton.setCompressionResistanceHigh()

        view.addSubview(cameraModeButton)
        cameraModeButton.setCompressionResistanceHigh()

        view.addSubview(mediaLibraryModeButton)
        mediaLibraryModeButton.setCompressionResistanceHigh()

        if UIDevice.current.isIPad {
            let buttonSpacing: CGFloat = 28
            // `doneButton` is our widest button, so we position it relative to the superview
            // margin, and position other buttons relative to `doneButton`. This ensures
            // `donebutton` has a good distance from the edge *and* that all the buttons in the
            // cluster are centered WRT eachother.
            doneButton.autoPinEdge(toSuperviewMargin: .trailing)
            doneButton.bottomAnchor.constraint(equalTo: view.layoutMarginsGuide.bottomAnchor, constant: -buttonSpacing).isActive = true

            batchModeButton.autoAlignAxis(.vertical, toSameAxisOf: doneButton)
            batchModeButton.autoAlignAxis(.horizontal, toSameAxisOf: doneButton)

            cameraModeButton.autoAlignAxis(.vertical, toSameAxisOf: doneButton)
            cameraModeButton.autoPinEdge(.bottom, to: .top, of: doneButton, withOffset: -buttonSpacing)

            mediaLibraryModeButton.autoAlignAxis(.vertical, toSameAxisOf: cameraModeButton)
            mediaLibraryModeButton.autoAlignAxis(.horizontal, toSameAxisOf: cameraModeButton)
        } else {
            // we pin to edges rather than margin, because on notched devices the safeAreaInsets/margins change
            // as the device rotates *EVEN THOUGH* the interface is locked to portrait.

            batchModeButton.centerYAnchor.constraint(equalTo: view.bottomAnchor, constant: bottomButtonsCenterOffset).isActive = true
            batchModeButton.autoPinEdge(toSuperviewEdge: .trailing, withInset: 16)

            doneButton.centerYAnchor.constraint(equalTo: view.bottomAnchor, constant: bottomButtonsCenterOffset).isActive = true
            doneButton.autoPinEdge(toSuperviewEdge: .trailing, withInset: 16)

            cameraModeButton.centerYAnchor.constraint(equalTo: view.bottomAnchor, constant: bottomButtonsCenterOffset).isActive = true
            cameraModeButton.autoPinEdge(toSuperviewEdge: .leading, withInset: 16)

            mediaLibraryModeButton.centerYAnchor.constraint(equalTo: view.bottomAnchor, constant: bottomButtonsCenterOffset).isActive = true
            mediaLibraryModeButton.autoPinEdge(toSuperviewEdge: .leading, withInset: 16)
        }
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        DispatchQueue.main.async {
            // pre-layout views for snappier response should the user
            // decide to switch

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

    private(set) var isPickingAsDocument = false
    @objc
    public class func asMediaDocumentPicker() -> SendMediaNavigationController {
        let navController = SendMediaNavigationController()
        navController.isPickingAsDocument = true
        navController.setViewControllers([navController.mediaLibraryViewController], animated: false)
        return navController
    }

    private var isForcingBatchSelectInMediaLibrary = true

    private var isShowingMediaLibrary = false
    private var isRecordingMovie = false

    var isInBatchSelectMode: Bool {
        get {
            if isForcingBatchSelectInMediaLibrary && isShowingMediaLibrary {
                return true
            }
            return self.batchModeButton.isSelected
        }

        set {
            let didChange = newValue != isInBatchSelectMode
            self.batchModeButton.isSelected = newValue

            if didChange {
                mediaLibraryViewController.batchSelectModeDidChange()
                guard let topViewController = viewControllers.last else {
                    return
                }
                updateViewState(topViewController: topViewController, animated: false)
            }
        }
    }

    func updateViewState(topViewController: UIViewController, animated: Bool) {
        let changes: () -> Void
        switch topViewController {
        case is AttachmentApprovalViewController:
            changes = {
                self.isShowingMediaLibrary = false
                self.batchModeButton.alpha = 0
                self.doneButton.alpha = 0
                self.cameraModeButton.alpha = 0
                self.mediaLibraryModeButton.alpha = 0
            }
        case let mediaLibraryView as ImagePickerGridController:
            changes = {
                self.isShowingMediaLibrary = true
                let showDoneButton = self.isInBatchSelectMode && self.attachmentCount > 0
                self.doneButton.alpha = showDoneButton ? 1 : 0

                self.batchModeButton.alpha = showDoneButton || self.isForcingBatchSelectInMediaLibrary ? 0 : 1
                self.batchModeButton.isBeingPresentedOverPhotoCapture = false

                self.cameraModeButton.alpha = 1
                self.cameraModeButton.isBeingPresentedOverPhotoCapture = false

                self.mediaLibraryModeButton.alpha = 0
                self.mediaLibraryModeButton.isBeingPresentedOverPhotoCapture = false

                mediaLibraryView.applyBatchSelectMode()
            }
        case is PhotoCaptureViewController:
            changes = {
                self.isShowingMediaLibrary = false
                let showDoneButton = self.isInBatchSelectMode && self.attachmentCount > 0
                self.doneButton.alpha = !showDoneButton || self.isRecordingMovie ? 0 : 1

                self.batchModeButton.alpha = showDoneButton || self.isRecordingMovie ? 0 : 1
                self.batchModeButton.isBeingPresentedOverPhotoCapture = true

                self.cameraModeButton.alpha = 0
                self.cameraModeButton.isBeingPresentedOverPhotoCapture = true

                self.mediaLibraryModeButton.alpha = self.isRecordingMovie ? 0 : 1
                self.mediaLibraryModeButton.isBeingPresentedOverPhotoCapture = true
            }
        case is ConversationPickerViewController:
            changes = {
                self.doneButton.alpha = 0
                self.batchModeButton.alpha = 0
                self.cameraModeButton.alpha = 0
                self.mediaLibraryModeButton.alpha = 0
            }
        default:
            owsFailDebug("unexpected topViewController: \(topViewController)")
            changes = { }
        }

        if animated {
            UIView.animate(withDuration: 0.3, animations: changes)
        } else {
            changes()
        }
        doneButton.updateCount()
    }

    func fadeTo(viewControllers: [UIViewController], duration: CFTimeInterval) {
        let transition: CATransition = CATransition()
        transition.duration = duration
        transition.type = CATransitionType.fade
        view.layer.add(transition, forKey: nil)
        setViewControllers(viewControllers, animated: false)
    }

    // MARK: - Events

    private func didTapBatchModeButton() {
        isInBatchSelectMode = !isInBatchSelectMode
        assert(isInBatchSelectMode || attachmentCount <= 1)
    }

    private func didTapCameraModeButton() {
        self.ows_askForCameraPermissions { isGranted in
            guard isGranted else { return }

            BenchEventStart(title: "Show-Camera", eventId: "Show-Camera")
            self.fadeTo(viewControllers: [self.captureViewController], duration: 0.08)
        }
    }

    private func didTapMediaLibraryModeButton() {
        self.ows_askForMediaLibraryPermissions { isGranted in
            guard isGranted else { return }

            BenchEventStart(title: "Show-Media-Library", eventId: "Show-Media-Library")
            self.fadeTo(viewControllers: [self.mediaLibraryViewController], duration: 0.08)
        }
    }

    // MARK: Views
    public static let bottomButtonWidth: CGFloat = 44

    private lazy var doneButton: DoneButton = {
        let button = DoneButton()
        button.delegate = self
        button.setShadow()

        return button
    }()

    private lazy var batchModeButton: SendMediaBottomButton = {
        return SendMediaBottomButton(imageName: "create-album-filled-28",
                                     tintColor: .ows_white,
                                     diameter: type(of: self).bottomButtonWidth,
                                     block: { [weak self] in self?.didTapBatchModeButton() })
    }()

    private lazy var cameraModeButton: SendMediaBottomButton = {
        return SendMediaBottomButton(imageName: "camera-outline-28",
                                     tintColor: .ows_white,
                                     diameter: type(of: self).bottomButtonWidth,
                                     block: { [weak self] in self?.didTapCameraModeButton() })
    }()

    private lazy var mediaLibraryModeButton: SendMediaBottomButton = {
        return SendMediaBottomButton(imageName: "photo-outline-28",
                                     tintColor: .ows_white,
                                     diameter: type(of: self).bottomButtonWidth,
                                     block: { [weak self] in self?.didTapMediaLibraryModeButton() })
    }()

    // MARK: State

    private var attachmentDraftCollection: AttachmentDraftCollection = .empty

    private var attachmentApprovalItemPromises: [Promise<AttachmentApprovalItem>] {
        return attachmentDraftCollection.attachmentApprovalItemPromises
    }

    // MARK: Child VC's

    fileprivate lazy var captureViewController: PhotoCaptureViewController = {
        let vc = PhotoCaptureViewController()
        vc.delegate = self

        return vc
    }()

    private lazy var mediaLibraryViewController: ImagePickerGridController = {
        let vc = ImagePickerGridController()
        vc.delegate = self

        return vc
    }()

    private func pushApprovalViewController(
        attachmentApprovalItems: [AttachmentApprovalItem],
        options: AttachmentApprovalViewControllerOptions = .canAddMore,
        animated: Bool
    ) {
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

            let confirmAbandonText = NSLocalizedString("SEND_MEDIA_CONFIRM_ABANDON_ALBUM", comment: "alert action, confirming the user wants to exit the media flow and abandon any photos they've taken")
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

        switch viewController {
        case is PhotoCaptureViewController:
            if attachmentDraftCollection.count == 1 && !isInBatchSelectMode {
                // User is navigating "back" to the previous view, indicating
                // they want to discard the previously captured item
                discardDraft()
            }
        case is ImagePickerGridController:
            if attachmentDraftCollection.count == 1 && !isInBatchSelectMode {
                isInBatchSelectMode = true
                mediaLibraryViewController.reloadData()
            }
        default:
            break
        }

        updateViewState(topViewController: viewController, animated: false)
    }

    // In case back navigation was canceled, we re-apply whatever is showing.
    func navigationController(_ navigationController: UINavigationController, didShow viewController: UIViewController, animated: Bool) {
        updateNavbarTheme(for: viewController, animated: animated)
        updateViewState(topViewController: viewController, animated: false)
    }

    func navigationControllerSupportedInterfaceOrientations(_ navigationController: UINavigationController) -> UIInterfaceOrientationMask {
        return navigationController.topViewController?.supportedInterfaceOrientations ?? UIDevice.current.defaultSupportedOrienations
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
            showNavbar(.clear)
        case is ImagePickerGridController:
            showNavbar(.alwaysDark)
        case is ConversationPickerViewController:
            showNavbar(.default)
        default:
            owsFailDebug("unexpected viewController: \(viewController)")
            return
        }
    }

    // MARK: - Too Many

    func showTooManySelectedToast() {
        Logger.info("")

        let toastFormat = NSLocalizedString("IMAGE_PICKER_CAN_SELECT_NO_MORE_TOAST_FORMAT",
                                            comment: "Momentarily shown to the user when attempting to select more images than is allowed. Embeds {{max number of items}} that can be shared.")

        let toastText = String(format: toastFormat, NSNumber(value: SignalAttachment.maxAttachmentsAllowed))

        let toastController = ToastController(text: toastText)

        let kToastInset: CGFloat = 10
        let bottomInset = kToastInset + view.layoutMargins.bottom

        toastController.presentToastView(fromBottomOfView: view, inset: bottomInset)
    }
}

extension SendMediaNavigationController: PhotoCaptureViewControllerDelegate {

    func photoCaptureViewController(_ photoCaptureViewController: PhotoCaptureViewController, didFinishProcessingAttachment attachment: SignalAttachment) {
        guard let sendMediaNavDelegate = self.sendMediaNavDelegate else { return }
        let cameraCaptureAttachment = CameraCaptureAttachment(signalAttachment: attachment, canSave: sendMediaNavDelegate.sendMediaNavCanSaveAttachments)
        attachmentDraftCollection.append(.camera(attachment: cameraCaptureAttachment))
        if isInBatchSelectMode {
            updateViewState(topViewController: photoCaptureViewController, animated: false)
        } else {
            pushApprovalViewController(attachmentApprovalItems: [cameraCaptureAttachment.attachmentApprovalItem],
                                       animated: true)
        }
    }

    func photoCaptureViewControllerDidCancel(_ photoCaptureViewController: PhotoCaptureViewController) {
        let dontAbandonText = NSLocalizedString("SEND_MEDIA_RETURN_TO_CAMERA", comment: "alert action when the user decides not to cancel the media flow after all.")
        didRequestExit(dontAbandonText: dontAbandonText)
    }

    func photoCaptureViewControllerDidTryToCaptureTooMany(_ photoCaptureViewController: PhotoCaptureViewController) {
        showTooManySelectedToast()
    }

    func photoCaptureViewControllerCanCaptureMoreItems(_ photoCaptureViewController: PhotoCaptureViewController) -> Bool {
        return attachmentCount < SignalAttachment.maxAttachmentsAllowed
    }

    func discardDraft() {
        assert(attachmentDraftCollection.attachmentDrafts.count <= 1)
        if let lastAttachmentDraft = attachmentDraftCollection.attachmentDrafts.last {
            attachmentDraftCollection.remove(lastAttachmentDraft)
        }
        assert(attachmentDraftCollection.attachmentDrafts.count == 0)
    }

    func photoCaptureViewController(_ photoCaptureViewController: PhotoCaptureViewController, isRecordingMovie: Bool) {
        assert(self.isRecordingMovie != isRecordingMovie)
        self.isRecordingMovie = isRecordingMovie
        updateViewState(topViewController: photoCaptureViewController, animated: true)
    }
}

extension SendMediaNavigationController: ImagePickerGridControllerDelegate {

    func imagePickerDidCompleteSelection(_ imagePicker: ImagePickerGridController) {
        showApprovalAfterProcessingAnyMediaLibrarySelections()
    }

    func imagePickerDidCancel(_ imagePicker: ImagePickerGridController) {
        let dontAbandonText = NSLocalizedString("SEND_MEDIA_RETURN_TO_MEDIA_LIBRARY", comment: "alert action when the user decides not to cancel the media flow after all.")
        didRequestExit(dontAbandonText: dontAbandonText)
    }

    func showApprovalAfterProcessingAnyMediaLibrarySelections() {
        let backgroundBlock: (ModalActivityIndicatorViewController) -> Void = { modal in
            let approvalItemsPromise = when(fulfilled: self.attachmentDraftCollection.attachmentApprovalItemPromises)
            firstly { () -> Promise<Swift.Result<[AttachmentApprovalItem], Error>> in
                return race(
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

    func imagePicker(_ imagePicker: ImagePickerGridController, isAssetSelected asset: PHAsset) -> Bool {
        return attachmentDraftCollection.hasPickerAttachment(forAsset: asset)
    }

    func imagePicker(_ imagePicker: ImagePickerGridController, didSelectAsset asset: PHAsset, attachmentPromise: Promise<SignalAttachment>) {
        guard let sendMediaNavDelegate = sendMediaNavDelegate else { return }

        guard !attachmentDraftCollection.hasPickerAttachment(forAsset: asset) else {
            return
        }

        let attachmentApprovalItemPromise = attachmentPromise.map { attachment in
            AttachmentApprovalItem(attachment: attachment,
                                   canSave: sendMediaNavDelegate.sendMediaNavCanSaveAttachments)
        }

        let libraryMedia = MediaLibraryAttachment(asset: asset, attachmentApprovalItemPromise: attachmentApprovalItemPromise)
        attachmentDraftCollection.append(.picker(attachment: libraryMedia))

        updateViewState(topViewController: imagePicker, animated: false)
    }

    func imagePicker(_ imagePicker: ImagePickerGridController, didDeselectAsset asset: PHAsset) {
        guard let draft = attachmentDraftCollection.pickerAttachment(forAsset: asset) else {
            return
        }
        attachmentDraftCollection.remove(.picker(attachment: draft))

        updateViewState(topViewController: imagePicker, animated: false)
    }

    func imagePickerCanSelectMoreItems(_ imagePicker: ImagePickerGridController) -> Bool {
        return attachmentCount < SignalAttachment.maxAttachmentsAllowed
    }

    func imagePickerDidTryToSelectTooMany(_ imagePicker: ImagePickerGridController) {
        showTooManySelectedToast()
    }
}

extension SendMediaNavigationController: AttachmentApprovalViewControllerDelegate {

    func attachmentApprovalDidAppear(_ attachmentApproval: AttachmentApprovalViewController) {
        updateViewState(topViewController: attachmentApproval, animated: true)
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
        assert(viewControllers.count == 2)

        // regardless of which VC we're going "back" to, we're in "batch" mode at this point.
        isInBatchSelectMode = true

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

    static func ==(lhs: CameraCaptureAttachment, rhs: CameraCaptureAttachment) -> Bool {
        return lhs.signalAttachment == rhs.signalAttachment
    }
}

private struct MediaLibraryAttachment: Hashable, Equatable {
    let asset: PHAsset
    let attachmentApprovalItemPromise: Promise<AttachmentApprovalItem>

    func hash(into hasher: inout Hasher) {
        hasher.combine(asset)
    }

    static func ==(lhs: MediaLibraryAttachment, rhs: MediaLibraryAttachment) -> Bool {
        return lhs.asset == rhs.asset
    }
}

extension SendMediaNavigationController: DoneButtonDelegate {
    var doneButtonCount: Int {
        return attachmentCount
    }

    fileprivate func doneButtonWasTapped(_ doneButton: DoneButton) {
        assert(attachmentDraftCollection.count > 0)
        showApprovalAfterProcessingAnyMediaLibrarySelections()
    }
}

private protocol DoneButtonDelegate: AnyObject {
    func doneButtonWasTapped(_ doneButton: DoneButton)
    var doneButtonCount: Int { get }
}

private class DoneButton: UIView {
    weak var delegate: DoneButtonDelegate?

    init() {
        super.init(frame: .zero)
        let tapGesture = UITapGestureRecognizer(target: self, action: #selector(didTap(tapGesture:)))
        addGestureRecognizer(tapGesture)

        let container = PillView()
        container.backgroundColor = .ows_white
        container.layoutMargins = UIEdgeInsets(top: 7, leading: 8, bottom: 7, trailing: 8)

        addSubview(container)
        container.autoPinEdgesToSuperviewMargins()

        let stackView = UIStackView(arrangedSubviews: [badge, chevron])
        stackView.axis = .horizontal
        stackView.alignment = .center
        stackView.spacing = 9

        container.addSubview(stackView)
        stackView.autoPinEdgesToSuperviewMargins()
    }

    let numberFormatter: NumberFormatter = NumberFormatter()

    func updateCount() {
        guard let delegate = delegate else {
            return
        }

        badgeLabel.text = numberFormatter.string(for: delegate.doneButtonCount)
    }

    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    // MARK: - Subviews

    private lazy var badge: UIView = {
        let badge = PillView()
        badge.layoutMargins = UIEdgeInsets(top: 4, leading: 4, bottom: 4, trailing: 4)
        badge.backgroundColor = .ows_accentBlue
        badge.addSubview(badgeLabel)
        badgeLabel.autoPinEdgesToSuperviewMargins()

        return badge
    }()

    private lazy var badgeLabel: UILabel = {
        let label = UILabel()
        label.textColor = .ows_white
        label.font = UIFont.ows_dynamicTypeSubheadline.ows_monospaced
        label.textAlignment = .center
        return label
    }()

    private lazy var chevron: UIView = {
        let image: UIImage
        if CurrentAppContext().isRTL {
            image = #imageLiteral(resourceName: "small_chevron_left")
        } else {
            image = #imageLiteral(resourceName: "small_chevron_right")
        }
        let chevron = UIImageView(image: image.withRenderingMode(.alwaysTemplate))
        chevron.contentMode = .scaleAspectFit
        chevron.tintColor = .ows_gray60
        chevron.autoSetDimensions(to: CGSize(width: 10, height: 18))

        return chevron
    }()

    @objc
    func didTap(tapGesture: UITapGestureRecognizer) {
        delegate?.doneButtonWasTapped(self)
    }
}
