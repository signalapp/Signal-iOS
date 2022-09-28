// Copyright © 2022 Rangeproof Pty Ltd. All rights reserved.

import UIKit
import Photos
import PromiseKit
import SignalUtilitiesKit

class SendMediaNavigationController: OWSNavigationController {

    // This is a sensitive constant, if you change it make sure to check
    // on iPhone5, 6, 6+, X, layouts.
    static let bottomButtonsCenterOffset: CGFloat = -50
    
    private let threadId: String
    
    // MARK: - Initialization
    
    init(threadId: String) {
        self.threadId = threadId
        
        super.init()
    }
    
    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    // MARK: - Overrides

    override var prefersStatusBarHidden: Bool { return true }

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

    public weak var sendMediaNavDelegate: SendMediaNavDelegate?

    @objc
    public class func showingCameraFirst(threadId: String) -> SendMediaNavigationController {
        let navController = SendMediaNavigationController(threadId: threadId)
        navController.viewControllers = [navController.captureViewController]

        return navController
    }

    @objc
    public class func showingMediaLibraryFirst(threadId: String) -> SendMediaNavigationController {
        let navController = SendMediaNavigationController(threadId: threadId)
        navController.viewControllers = [navController.mediaLibraryViewController]

        return navController
    }

    var isInBatchSelectMode = false {
        didSet {
            if oldValue != isInBatchSelectMode {
                mediaLibraryViewController.batchSelectModeDidChange()
                
                guard let topViewController = viewControllers.last else { return }
                
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
                batchModeButton.isHidden = isInBatchSelectMode
                doneButton.isHidden = !isInBatchSelectMode || (attachmentDraftCollection.count == 0 && mediaLibrarySelections.count == 0)
                cameraModeButton.isHidden = false
                mediaLibraryModeButton.isHidden = true
                
            case is PhotoCaptureViewController:
                batchModeButton.isHidden = isInBatchSelectMode
                doneButton.isHidden = !isInBatchSelectMode || (attachmentDraftCollection.count == 0 && mediaLibrarySelections.count == 0)
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
        // There's no way to _disable_ batch mode.
        isInBatchSelectMode = true
    }

    private func didTapCameraModeButton() {
        Permissions.requestCameraPermissionIfNeeded { [weak self] in
            self?.fadeTo(viewControllers: ((self?.captureViewController).map { [$0] } ?? []))
        }
    }

    private func didTapMediaLibraryModeButton() {
        Permissions.requestLibraryPermissionIfNeeded { [weak self] in
            self?.fadeTo(viewControllers: ((self?.mediaLibraryViewController).map { [$0] } ?? []))
        }
    }

    // MARK: Views
    public static let bottomButtonWidth: CGFloat = 44

    private lazy var doneButton: DoneButton = {
        let button = DoneButton()
        button.delegate = self

        return button
    }()

    private lazy var batchModeButton: UIButton = {
        let button = OWSButton(
            imageName: "media_send_batch_mode_disabled",
            tintColor: .backgroundPrimary,
            block: { [weak self] in self?.didTapBatchModeButton() }
        )
        button.clipsToBounds = true
        button.adjustsImageWhenHighlighted = false
        button.setThemeBackgroundColor(.textPrimary, for: .normal)
        button.setThemeBackgroundColor(.textSecondary, for: .highlighted)
        button.imageEdgeInsets = UIEdgeInsets(top: 10, left: 10, bottom: 10, right: 10)
        button.layer.cornerRadius = (SendMediaNavigationController.bottomButtonWidth / 2)
        button.set(.width, to: SendMediaNavigationController.bottomButtonWidth)
        button.set(.height, to: SendMediaNavigationController.bottomButtonWidth)

        return button
    }()

    private lazy var cameraModeButton: UIButton = {
        let button = OWSButton(
            imageName: "settings-avatar-camera-2",
            tintColor: .backgroundPrimary,
            block: { [weak self] in self?.didTapCameraModeButton() }
        )
        button.clipsToBounds = true
        button.adjustsImageWhenHighlighted = false
        button.setThemeBackgroundColor(.textPrimary, for: .normal)
        button.setThemeBackgroundColor(.textSecondary, for: .highlighted)
        button.imageEdgeInsets = UIEdgeInsets(top: 10, left: 10, bottom: 10, right: 10)
        button.layer.cornerRadius = (SendMediaNavigationController.bottomButtonWidth / 2)
        button.set(.width, to: SendMediaNavigationController.bottomButtonWidth)
        button.set(.height, to: SendMediaNavigationController.bottomButtonWidth)

        return button
    }()

    private lazy var mediaLibraryModeButton: UIButton = {
        let button = OWSButton(
            imageName: "actionsheet_camera_roll_black",
            tintColor: .backgroundPrimary,
            block: { [weak self] in self?.didTapMediaLibraryModeButton() }
        )
        button.clipsToBounds = true
        button.adjustsImageWhenHighlighted = false
        button.setThemeBackgroundColor(.textPrimary, for: .normal)
        button.setThemeBackgroundColor(.textSecondary, for: .highlighted)
        button.imageEdgeInsets = UIEdgeInsets(top: 10, left: 10, bottom: 10, right: 10)
        button.layer.cornerRadius = (SendMediaNavigationController.bottomButtonWidth / 2)
        button.set(.width, to: SendMediaNavigationController.bottomButtonWidth)
        button.set(.height, to: SendMediaNavigationController.bottomButtonWidth)

        return button
    }()

    // MARK: State

    private lazy var attachmentDraftCollection = AttachmentDraftCollection.empty // Lazy to avoid https://bugs.swift.org/browse/SR-6657

    private var attachments: [SignalAttachment] {
        return attachmentDraftCollection.attachmentDrafts.map { $0.attachment }
    }

    private lazy var mediaLibrarySelections = OrderedDictionary<PHAsset, MediaLibrarySelection>() // Lazy to avoid https://bugs.swift.org/browse/SR-6657

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

        let approvalViewController = AttachmentApprovalViewController(
            mode: .sharedNavigation,
            threadId: self.threadId,
            attachments: self.attachments
        )
        approvalViewController.approvalDelegate = self
        approvalViewController.messageText = sendMediaNavDelegate.sendMediaNavInitialMessageText(self)

        pushViewController(approvalViewController, animated: true)
    }

    private func didRequestExit() {
        guard attachmentDraftCollection.count > 0 else {
            self.sendMediaNavDelegate?.sendMediaNavDidCancel(self)
            return
        }
        
        let modal: ConfirmationModal = ConfirmationModal(
            info: ConfirmationModal.Info(
                title: "SEND_MEDIA_ABANDON_TITLE".localized(),
                confirmTitle: "SEND_MEDIA_CONFIRM_ABANDON_ALBUM".localized(),
                confirmStyle: .danger,
                cancelStyle: .alert_text,
                onConfirm: { [weak self] _ in
                    self?.sendMediaNavDelegate?.sendMediaNavDidCancel(self)
                }
            )
        )
        self.present(modal, animated: true)
    }
}

extension SendMediaNavigationController: UINavigationControllerDelegate {
    func navigationController(_ navigationController: UINavigationController, willShow viewController: UIViewController, animated: Bool) {
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
        self.updateButtons(topViewController: viewController)
    }
}

extension SendMediaNavigationController: PhotoCaptureViewControllerDelegate {
    func photoCaptureViewController(_ photoCaptureViewController: PhotoCaptureViewController, didFinishProcessingAttachment attachment: SignalAttachment) {
        attachmentDraftCollection.append(.camera(attachment: attachment))
        if isInBatchSelectMode {
            updateButtons(topViewController: photoCaptureViewController)
        }
        else {
            pushApprovalViewController()
        }
    }

    func photoCaptureViewControllerDidCancel(_ photoCaptureViewController: PhotoCaptureViewController) {
        didRequestExit()
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
        didRequestExit()
    }

    func showApprovalAfterProcessingAnyMediaLibrarySelections() {
        let mediaLibrarySelections: [MediaLibrarySelection] = self.mediaLibrarySelections.orderedValues

        let backgroundBlock: (ModalActivityIndicatorViewController) -> Void = { modal in
            let attachmentPromises: [Promise<MediaLibraryAttachment>] = mediaLibrarySelections.map { $0.promise }

            when(fulfilled: attachmentPromises)
                .map { attachments in
                    Logger.debug("built all attachments")
                    modal.dismiss {
                        self.attachmentDraftCollection.selectedFromPicker(attachments: attachments)
                        self.pushApprovalViewController()
                    }
                }
                .catch { error in
                    Logger.error("failed to prepare attachments. error: \(error)")
                    modal.dismiss { [weak self] in
                        let modal: ConfirmationModal = ConfirmationModal(
                            targetView: self?.view,
                            info: ConfirmationModal.Info(
                                title: "IMAGE_PICKER_FAILED_TO_PROCESS_ATTACHMENTS".localized(),
                                cancelTitle: "BUTTON_OK".localized(),
                                cancelStyle: .alert_text
                            )
                        )
                        self?.present(modal, animated: true)
                    }
                }
                .retainUntilComplete()
        }

        ModalActivityIndicatorViewController.present(
            fromViewController: self,
            canCancel: false,
            onAppear: backgroundBlock
        )
    }

    func imagePicker(_ imagePicker: ImagePickerGridController, isAssetSelected asset: PHAsset) -> Bool {
        return mediaLibrarySelections.hasValue(forKey: asset)
    }

    func imagePicker(_ imagePicker: ImagePickerGridController, didSelectAsset asset: PHAsset, attachmentPromise: Promise<SignalAttachment>) {
        guard !mediaLibrarySelections.hasValue(forKey: asset) else { return }

        let libraryMedia = MediaLibrarySelection(asset: asset, signalAttachmentPromise: attachmentPromise)
        mediaLibrarySelections.append(key: asset, value: libraryMedia)
        updateButtons(topViewController: imagePicker)
    }

    func imagePicker(_ imagePicker: ImagePickerGridController, didDeselectAsset asset: PHAsset) {
        guard mediaLibrarySelections.hasValue(forKey: asset) else { return }
        
        mediaLibrarySelections.remove(key: asset)
        updateButtons(topViewController: imagePicker)
    }

    func imagePickerCanSelectAdditionalItems(_ imagePicker: ImagePickerGridController) -> Bool {
        return attachmentDraftCollection.count <= SignalAttachment.maxAttachmentsAllowed
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

    func attachmentApproval(_ attachmentApproval: AttachmentApprovalViewController, didApproveAttachments attachments: [SignalAttachment], forThreadId threadId: String, messageText: String?) {
        sendMediaNavDelegate?.sendMediaNav(self, didApproveAttachments: attachments, forThreadId: threadId, messageText: messageText)
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

private final class AttachmentDraftCollection {
    lazy var attachmentDrafts = [AttachmentDraft]() // Lazy to avoid https://bugs.swift.org/browse/SR-6657

    static var empty: AttachmentDraftCollection {
        return AttachmentDraftCollection(attachmentDrafts: [])
    }
    
    init(attachmentDrafts: [AttachmentDraft]) {
        self.attachmentDrafts = attachmentDrafts
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

    func append(_ element: AttachmentDraft) {
        attachmentDrafts.append(element)
    }

    func remove(attachment: SignalAttachment) {
        attachmentDrafts.removeAll { $0.attachment == attachment }
    }

    func selectedFromPicker(attachments: [MediaLibraryAttachment]) {
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
        return attachmentDraftCollection.count - attachmentDraftCollection.pickerAttachments.count + mediaLibrarySelections.count
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
    let numberFormatter: NumberFormatter = NumberFormatter()
    
    private var didTouchDownInside: Bool = false
    
    // MARK: - UI
    
    private let container: UIView = {
        let result: UIView = UIView()
        result.themeBackgroundColor = .textPrimary
        result.layer.cornerRadius = 20
        
        return result
    }()
    
    private lazy var badge: CircleView = {
        let result: CircleView = CircleView()
        result.themeBackgroundColor = .primary

        return result
    }()

    private lazy var badgeLabel: UILabel = {
        let result: UILabel = UILabel()
        result.font = .ows_dynamicTypeSubheadline.ows_monospaced()
        result.themeTextColor = .black   // Will render on the primary color so should always be black
        result.textAlignment = .center
        
        return result
    }()

    private lazy var chevron: UIView = {
        let image: UIImage = {
            guard CurrentAppContext().isRTL else { return #imageLiteral(resourceName: "small_chevron_right") }
            
            return #imageLiteral(resourceName: "small_chevron_left")
        }()
        let result: UIImageView = UIImageView(image: image.withRenderingMode(.alwaysTemplate))
        result.contentMode = .scaleAspectFit
        result.themeTintColor = .backgroundPrimary
        result.set(.width, to: 10)
        result.set(.height, to: 18)

        return result
    }()
    
    // MARK: - Lifecycle

    init() {
        super.init(frame: .zero)

        let tapGesture = UITapGestureRecognizer(target: self, action: #selector(didTap(tapGesture:)))
        addGestureRecognizer(tapGesture)
        
        addSubview(container)
        container.pin(to: self)
        
        badge.addSubview(badgeLabel)
        badgeLabel.pin(to: badge, withInset: 4)
        
        // Constrain to be a pill that is at least a circle, and maybe wider.
        badgeLabel.autoPin(toAspectRatio: 1.0, relation: .greaterThanOrEqual)
        NSLayoutConstraint.autoSetPriority(.defaultLow) {
            badgeLabel.autoPinToSquareAspectRatio()
        }

        let stackView = UIStackView(arrangedSubviews: [badge, chevron])
        stackView.axis = .horizontal
        stackView.alignment = .center
        stackView.spacing = 9

        container.addSubview(stackView)
        stackView.pin(.top, to: .top, of: container, withInset: 7)
        stackView.pin(.leading, to: .leading, of: container, withInset: 8)
        stackView.pin(.trailing, to: .trailing, of: container, withInset: -8)
        stackView.pin(.bottom, to: .bottom, of: container, withInset: -7)
    }

    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    // MARK: - Functions
    
    func updateCount() {
        guard let delegate = delegate else { return }

        badgeLabel.text = numberFormatter.string(for: delegate.doneButtonCount)
    }
    
    // MARK: - Interaction

    @objc func didTap(tapGesture: UITapGestureRecognizer) {
        delegate?.doneButtonWasTapped(self)
    }
    
    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard
            isUserInteractionEnabled,
            let location: CGPoint = touches.first?.location(in: self),
            bounds.contains(location)
        else { return }
        
        didTouchDownInside = true
        container.themeBackgroundColor = .textSecondary
    }

    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard
            isUserInteractionEnabled,
            let location: CGPoint = touches.first?.location(in: self),
            bounds.contains(location),
            didTouchDownInside
        else {
            if didTouchDownInside {
                container.themeBackgroundColor = .textPrimary
            }
            return
        }
        
        container.themeBackgroundColor = .textSecondary
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        if didTouchDownInside {
            container.themeBackgroundColor = .textPrimary
        }
        
        didTouchDownInside = false
    }
    
    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) {
        if didTouchDownInside {
            container.themeBackgroundColor = .textPrimary
        }
        
        didTouchDownInside = false
    }
}

// MARK: - SendMediaNavDelegate

protocol SendMediaNavDelegate: AnyObject {
    func sendMediaNavDidCancel(_ sendMediaNavigationController: SendMediaNavigationController?)
    func sendMediaNav(_ sendMediaNavigationController: SendMediaNavigationController, didApproveAttachments attachments: [SignalAttachment], forThreadId threadId: String, messageText: String?)

    func sendMediaNavInitialMessageText(_ sendMediaNavigationController: SendMediaNavigationController) -> String?
    func sendMediaNav(_ sendMediaNavigationController: SendMediaNavigationController, didChangeMessageText newMessageText: String?)
}
