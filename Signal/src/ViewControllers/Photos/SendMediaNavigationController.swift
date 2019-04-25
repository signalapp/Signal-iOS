//
//  Copyright (c) 2019 Open Whisper Systems. All rights reserved.
//

import Foundation
import Photos
import PromiseKit

@objc
protocol SendMediaNavDelegate: AnyObject {
    func sendMediaNavDidCancel(_ sendMediaNavigationController: SendMediaNavigationController)
    func sendMediaNav(_ sendMediaNavigationController: SendMediaNavigationController, didApproveAttachments attachments: [SignalAttachment], messageText: String?)

    func sendMediaNavInitialMessageText(_ sendMediaNavigationController: SendMediaNavigationController) -> String?
    func sendMediaNav(_ sendMediaNavigationController: SendMediaNavigationController, didChangeMessageText newMessageText: String?)
}

@objc
class SendMediaNavigationController: OWSNavigationController {

    // This is a sensitive constant, if you change it make sure to check
    // on iPhone5, 6, 6+, X, layouts.
    static let bottomButtonsCenterOffset: CGFloat = -34

    var attachmentCount: Int {
        return attachmentDraftCollection.count - attachmentDraftCollection.pickerAttachments.count + mediaLibrarySelections.count
    }

    // MARK: - Overrides

    override var prefersStatusBarHidden: Bool {
        guard !OWSWindowManager.shared().hasCall() else {
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
        batchModeButton.centerYAnchor.constraint(equalTo: view.layoutMarginsGuide.bottomAnchor, constant: bottomButtonsCenterOffset).isActive = true
        batchModeButton.autoPinEdge(toSuperviewMargin: .trailing)

        view.addSubview(doneButton)
        doneButton.setCompressionResistanceHigh()
        doneButton.centerYAnchor.constraint(equalTo: view.layoutMarginsGuide.bottomAnchor, constant: bottomButtonsCenterOffset).isActive = true
        doneButton.autoPinEdge(toSuperviewMargin: .trailing)

        view.addSubview(cameraModeButton)
        cameraModeButton.setCompressionResistanceHigh()
        cameraModeButton.centerYAnchor.constraint(equalTo: view.layoutMarginsGuide.bottomAnchor, constant: bottomButtonsCenterOffset).isActive = true
        cameraModeButton.autoPinEdge(toSuperviewMargin: .leading)

        view.addSubview(mediaLibraryModeButton)
        mediaLibraryModeButton.setCompressionResistanceHigh()
        mediaLibraryModeButton.centerYAnchor.constraint(equalTo: view.layoutMarginsGuide.bottomAnchor, constant: bottomButtonsCenterOffset).isActive = true
        mediaLibraryModeButton.autoPinEdge(toSuperviewMargin: .leading)
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

    var isInBatchSelectMode: Bool {
        get {
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
                updateButtons(topViewController: topViewController)
            }
        }
    }

    func updateButtons(topViewController: UIViewController) {
        switch topViewController {
        case is AttachmentApprovalViewController:
            batchModeButton.isHidden = true
            doneButton.isHidden = true
            cameraModeButton.isHidden = true
            mediaLibraryModeButton.isHidden = true
        case is ImagePickerGridController:
            let showDoneButton = isInBatchSelectMode && attachmentCount > 0
            batchModeButton.isHidden = showDoneButton
            doneButton.isHidden = !showDoneButton
            cameraModeButton.isHidden = false
            mediaLibraryModeButton.isHidden = true
        case is PhotoCaptureViewController:
            let showDoneButton = isInBatchSelectMode && attachmentCount > 0
            batchModeButton.isHidden = showDoneButton
            doneButton.isHidden = !showDoneButton
            cameraModeButton.isHidden = true
            mediaLibraryModeButton.isHidden = false
        default:
            owsFailDebug("unexpected topViewController: \(topViewController)")
        }

        doneButton.updateCount()
    }

    func fadeTo(viewControllers: [UIViewController]) {
        let transition: CATransition = CATransition()
        transition.duration = 0.1
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
        fadeTo(viewControllers: [captureViewController])
    }

    private func didTapMediaLibraryModeButton() {
        fadeTo(viewControllers: [mediaLibraryViewController])
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

    private lazy var cameraModeButton: UIView = {
        return SendMediaBottomButton(imageName: "camera-filled-28",
                                     tintColor: .ows_white,
                                     diameter: type(of: self).bottomButtonWidth,
                                     block: { [weak self] in self?.didTapCameraModeButton() })
    }()

    private lazy var mediaLibraryModeButton: UIView = {
        return SendMediaBottomButton(imageName: "photo-filled-28",
                                     tintColor: .ows_white,
                                     diameter: type(of: self).bottomButtonWidth,
                                     block: { [weak self] in self?.didTapMediaLibraryModeButton() })
    }()

    // MARK: State

    private var attachmentDraftCollection: AttachmentDraftCollection = .empty

    private var attachments: [SignalAttachment] {
        return attachmentDraftCollection.attachmentDrafts.map { $0.attachment }
    }

    private let mediaLibrarySelections: OrderedDictionary<PHAsset, MediaLibrarySelection> = OrderedDictionary()

    // MARK: Child VC's

    private lazy var captureViewController: PhotoCaptureViewController = {
        let vc = PhotoCaptureViewController()
        vc.delegate = self

        return vc
    }()

    private lazy var mediaLibraryViewController: ImagePickerGridController = {
        let vc = ImagePickerGridController()
        vc.delegate = self

        return vc
    }()

    private func pushApprovalViewController() {
        guard let sendMediaNavDelegate = self.sendMediaNavDelegate else {
            owsFailDebug("sendMediaNavDelegate was unexpectedly nil")
            return
        }

        let approvalViewController = AttachmentApprovalViewController(mode: .sharedNavigation, attachments: self.attachments)
        approvalViewController.approvalDelegate = self
        approvalViewController.messageText = sendMediaNavDelegate.sendMediaNavInitialMessageText(self)

        pushViewController(approvalViewController, animated: true)
    }

    private func didRequestExit(dontAbandonText: String) {
        if attachmentDraftCollection.count == 0 {
            self.sendMediaNavDelegate?.sendMediaNavDidCancel(self)
        } else {
            let alertTitle = NSLocalizedString("SEND_MEDIA_ABANDON_TITLE", comment: "alert title when user attempts to leave the send media flow when they have an in-progress album")

            let alert = UIAlertController(title: alertTitle, message: nil, preferredStyle: .alert)

            let confirmAbandonText = NSLocalizedString("SEND_MEDIA_CONFIRM_ABANDON_ALBUM", comment: "alert action, confirming the user wants to exit the media flow and abandon any photos they've taken")
            let confirmAbandonAction = UIAlertAction(title: confirmAbandonText,
                                                     style: .destructive,
                                                     handler: { [weak self] _ in
                                                        guard let self = self else { return }
                                                        self.sendMediaNavDelegate?.sendMediaNavDidCancel(self)
            })
            alert.addAction(confirmAbandonAction)
            let dontAbandonAction = UIAlertAction(title: dontAbandonText,
                                                  style: .default,
                                                  handler: { _ in  })
            alert.addAction(dontAbandonAction)

            self.presentAlert(alert)
        }
    }
}

extension SendMediaNavigationController: UINavigationControllerDelegate {
    func navigationController(_ navigationController: UINavigationController, willShow viewController: UIViewController, animated: Bool) {
        if let navbarTheme = preferredNavbarTheme(viewController: viewController) {
            if let owsNavBar = navigationBar as? OWSNavigationBar {
                owsNavBar.overrideTheme(type: navbarTheme)
            } else {
                owsFailDebug("unexpected navigationBar: \(navigationBar)")
            }
        }

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
                self.mediaLibraryViewController.batchSelectModeDidChange()
            }
        default:
            break
        }

        self.updateButtons(topViewController: viewController)
    }

    // In case back navigation was canceled, we re-apply whatever is showing.
    func navigationController(_ navigationController: UINavigationController, didShow viewController: UIViewController, animated: Bool) {
        if let navbarTheme = preferredNavbarTheme(viewController: viewController) {
            if let owsNavBar = navigationBar as? OWSNavigationBar {
                owsNavBar.overrideTheme(type: navbarTheme)
            } else {
                owsFailDebug("unexpected navigationBar: \(navigationBar)")
            }
        }
        self.updateButtons(topViewController: viewController)
    }

    // MARK: - Helpers

    private func preferredNavbarTheme(viewController: UIViewController) -> OWSNavigationBar.NavigationBarThemeOverride? {
        switch viewController {
        case is AttachmentApprovalViewController:
            return .clear
        case is ImagePickerGridController:
            return .alwaysDark
        case is PhotoCaptureViewController:
            return .clear
        default:
            owsFailDebug("unexpected viewController: \(viewController)")
            return nil
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
        attachmentDraftCollection.append(.camera(attachment: attachment))
        if isInBatchSelectMode {
            updateButtons(topViewController: photoCaptureViewController)
        } else {
            pushApprovalViewController()
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
            attachmentDraftCollection.remove(attachment: lastAttachmentDraft.attachment)
        }
        assert(attachmentDraftCollection.attachmentDrafts.count == 0)
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
        let mediaLibrarySelections: [MediaLibrarySelection] = self.mediaLibrarySelections.orderedValues

        let backgroundBlock: (ModalActivityIndicatorViewController) -> Void = { modal in
            let attachmentPromises: [Promise<MediaLibraryAttachment>] = mediaLibrarySelections.map { $0.promise }

            when(fulfilled: attachmentPromises).map { attachments in
                Logger.debug("built all attachments")
                modal.dismiss {
                    self.attachmentDraftCollection.selectedFromPicker(attachments: attachments)
                    self.pushApprovalViewController()
                }
            }.catch { error in
                Logger.error("failed to prepare attachments. error: \(error)")
                modal.dismiss {
                    OWSAlerts.showAlert(title: NSLocalizedString("IMAGE_PICKER_FAILED_TO_PROCESS_ATTACHMENTS", comment: "alert title"))
                }
            }.retainUntilComplete()
        }

        ModalActivityIndicatorViewController.present(fromViewController: self,
                                                     canCancel: false,
                                                     backgroundBlock: backgroundBlock)
    }

    func imagePicker(_ imagePicker: ImagePickerGridController, isAssetSelected asset: PHAsset) -> Bool {
        return mediaLibrarySelections.hasValue(forKey: asset)
    }

    func imagePicker(_ imagePicker: ImagePickerGridController, didSelectAsset asset: PHAsset, attachmentPromise: Promise<SignalAttachment>) {
        guard !mediaLibrarySelections.hasValue(forKey: asset) else {
            return
        }

        let libraryMedia = MediaLibrarySelection(asset: asset, signalAttachmentPromise: attachmentPromise)
        mediaLibrarySelections.append(key: asset, value: libraryMedia)

        updateButtons(topViewController: imagePicker)
    }

    func imagePicker(_ imagePicker: ImagePickerGridController, didDeselectAsset asset: PHAsset) {
        guard mediaLibrarySelections.hasValue(forKey: asset) else {
            return
        }
        mediaLibrarySelections.remove(key: asset)

        updateButtons(topViewController: imagePicker)
    }

    func imagePickerCanSelectMoreItems(_ imagePicker: ImagePickerGridController) -> Bool {
        return attachmentCount < SignalAttachment.maxAttachmentsAllowed
    }

    func imagePickerDidTryToSelectTooMany(_ imagePicker: ImagePickerGridController) {
        showTooManySelectedToast()
    }
}

extension SendMediaNavigationController: AttachmentApprovalViewControllerDelegate {
    func attachmentApproval(_ attachmentApproval: AttachmentApprovalViewController, didChangeMessageText newMessageText: String?) {
        sendMediaNavDelegate?.sendMediaNav(self, didChangeMessageText: newMessageText)
    }

    func attachmentApproval(_ attachmentApproval: AttachmentApprovalViewController, didRemoveAttachment attachment: SignalAttachment) {
        guard let removedDraft = attachmentDraftCollection.attachmentDrafts.first(where: { $0.attachment == attachment}) else {
            owsFailDebug("removedDraft was unexpectedly nil")
            return
        }

        switch removedDraft.source {
        case .picker(attachment: let pickerAttachment):
            mediaLibrarySelections.remove(key: pickerAttachment.asset)
        case .camera(attachment: _):
            break
        }

        attachmentDraftCollection.remove(attachment: attachment)
    }

    func attachmentApproval(_ attachmentApproval: AttachmentApprovalViewController, didApproveAttachments attachments: [SignalAttachment], messageText: String?) {
        sendMediaNavDelegate?.sendMediaNav(self, didApproveAttachments: attachments, messageText: messageText)
    }

    func attachmentApprovalDidCancel(_ attachmentApproval: AttachmentApprovalViewController) {
        sendMediaNavDelegate?.sendMediaNavDidCancel(self)
    }

    func attachmentApprovalDidTapAddMore(_ attachmentApproval: AttachmentApprovalViewController) {
        // Current design dicates we'll go "back" to the single thing before us.
        assert(viewControllers.count == 2)

        // regardless of which VC we're going "back" to, we're in "batch" mode at this point.
        isInBatchSelectMode = true
        mediaLibraryViewController.batchSelectModeDidChange()

        popViewController(animated: true)
    }
}

private enum AttachmentDraft {
    case camera(attachment: SignalAttachment)
    case picker(attachment: MediaLibraryAttachment)
}

private extension AttachmentDraft {
    var attachment: SignalAttachment {
        switch self {
        case .camera(let cameraAttachment):
            return cameraAttachment
        case .picker(let pickerAttachment):
            return pickerAttachment.signalAttachment
        }
    }

    var source: AttachmentDraft {
        return self
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

    var cameraAttachments: [SignalAttachment] {
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

    mutating func remove(attachment: SignalAttachment) {
        attachmentDrafts = attachmentDrafts.filter { $0.attachment != attachment }
    }

    mutating func selectedFromPicker(attachments: [MediaLibraryAttachment]) {
        let pickedAttachments: Set<MediaLibraryAttachment> = Set(attachments)
        let oldPickerAttachments: Set<MediaLibraryAttachment> = Set(self.pickerAttachments)

        for removedAttachment in oldPickerAttachments.subtracting(pickedAttachments) {
            remove(attachment: removedAttachment.signalAttachment)
        }

        // enumerate over new attachments to maintain order from picker
        for attachment in attachments {
            guard !oldPickerAttachments.contains(attachment) else {
                continue
            }
            append(.picker(attachment: attachment))
        }
    }
}

private struct MediaLibrarySelection: Hashable, Equatable {
    let asset: PHAsset
    let signalAttachmentPromise: Promise<SignalAttachment>

    var hashValue: Int {
        return asset.hashValue
    }

    var promise: Promise<MediaLibraryAttachment> {
        let asset = self.asset
        return signalAttachmentPromise.map { signalAttachment in
            return MediaLibraryAttachment(asset: asset, signalAttachment: signalAttachment)
        }
    }

    static func ==(lhs: MediaLibrarySelection, rhs: MediaLibrarySelection) -> Bool {
        return lhs.asset == rhs.asset
    }
}

private struct MediaLibraryAttachment: Hashable, Equatable {
    let asset: PHAsset
    let signalAttachment: SignalAttachment

    public var hashValue: Int {
        return asset.hashValue
    }

    public static func == (lhs: MediaLibraryAttachment, rhs: MediaLibraryAttachment) -> Bool {
        return lhs.asset == rhs.asset
    }
}

extension SendMediaNavigationController: DoneButtonDelegate {
    var doneButtonCount: Int {
        return attachmentCount
    }

    fileprivate func doneButtonWasTapped(_ doneButton: DoneButton) {
        assert(attachmentDraftCollection.count > 0 || mediaLibrarySelections.count > 0)
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

        let container = UIView()
        container.backgroundColor = .ows_white
        container.layer.cornerRadius = 20
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
        let badge = CircleView()
        badge.layoutMargins = UIEdgeInsets(top: 4, leading: 4, bottom: 4, trailing: 4)
        badge.backgroundColor = .ows_signalBlue
        badge.addSubview(badgeLabel)
        badgeLabel.autoPinEdgesToSuperviewMargins()

        // Constrain to be a pill that is at least a circle, and maybe wider.
        badgeLabel.autoPin(toAspectRatio: 1.0, relation: .greaterThanOrEqual)
        NSLayoutConstraint.autoSetPriority(.defaultLow) {
            badgeLabel.autoPinToSquareAspectRatio()
        }

        return badge
    }()

    private lazy var badgeLabel: UILabel = {
        let label = UILabel()
        label.textColor = .ows_white
        label.font = UIFont.ows_dynamicTypeSubheadline.ows_monospaced()
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
