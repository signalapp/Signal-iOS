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
}

@objc
class SendMediaNavigationController: OWSNavigationController {

    // MARK: - Overrides

    override var prefersStatusBarHidden: Bool { return true }

    override func viewDidLoad() {
        super.viewDidLoad()

        self.delegate = self

        view.addSubview(batchModeButton)
        batchModeButton.setCompressionResistanceHigh()
        batchModeButton.autoPinEdge(toSuperviewMargin: .bottom)
        batchModeButton.autoPinEdge(toSuperviewMargin: .trailing)

        view.addSubview(doneButton)
        doneButton.setCompressionResistanceHigh()
        doneButton.autoPinEdge(toSuperviewMargin: .bottom)
        doneButton.autoPinEdge(toSuperviewMargin: .trailing)

        view.addSubview(cameraModeButton)
        cameraModeButton.setCompressionResistanceHigh()
        cameraModeButton.autoPinEdge(toSuperviewMargin: .bottom)
        cameraModeButton.autoPinEdge(toSuperviewMargin: .leading)

        view.addSubview(mediaLibraryModeButton)
        mediaLibraryModeButton.setCompressionResistanceHigh()
        mediaLibraryModeButton.autoPinEdge(toSuperviewMargin: .bottom)
        mediaLibraryModeButton.autoPinEdge(toSuperviewMargin: .leading)
    }

    // MARK: -

    @objc
    public weak var sendMediaNavDelegate: SendMediaNavDelegate?

    @objc
    public class func showingCameraFirst() -> SendMediaNavigationController {
        let navController = SendMediaNavigationController()
        navController.setViewControllers([navController.captureViewController], animated: false)
        navController.updateButtons()

        return navController
    }

    @objc
    public class func showingMediaLibraryFirst() -> SendMediaNavigationController {
        let navController = SendMediaNavigationController()
        navController.setViewControllers([navController.mediaLibraryViewController], animated: false)
        navController.updateButtons()

        return navController
    }

    var isInBatchSelectMode = false {
        didSet {
            if oldValue != isInBatchSelectMode {
                updateButtons()
                mediaLibraryViewController.batchSelectModeDidChange()
            }
        }
    }

    func updateButtons() {
        guard let topViewController = viewControllers.last else {
            return
        }

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
        transition.type = kCATransitionFade
        view.layer.add(transition, forKey: nil)
        setViewControllers(viewControllers, animated: false)
    }

    // MARK: - Events

    private func didTapBatchModeButton() {
        // There's no way to _disable_ batch mode.
        isInBatchSelectMode = true
    }

    private func didTapCameraModeButton() {
        fadeTo(viewControllers: [captureViewController])
        updateButtons()
    }

    private func didTapMediaLibraryModeButton() {
        fadeTo(viewControllers: [mediaLibraryViewController])
        updateButtons()
    }

    // MARK: Views

    private lazy var doneButton: DoneButton = {
        let button = DoneButton()
        button.delegate = self

        return button
    }()

    private lazy var batchModeButton: UIButton = {
        let button = OWSButton(imageName: "media_send_batch_mode_disabled",
                               tintColor: .ows_gray60,
                               block: { [weak self] in self?.didTapBatchModeButton() })

        let width: CGFloat = 44
        button.autoSetDimensions(to: CGSize(width: width, height: width))
        button.layer.cornerRadius = width / 2
        button.imageEdgeInsets = UIEdgeInsets(top: 10, left: 10, bottom: 10, right: 10)
        button.backgroundColor = .ows_white

        return button
    }()

    private lazy var cameraModeButton: UIButton = {
        let button = OWSButton(imageName: "settings-avatar-camera-2",
                               tintColor: .ows_gray60,
                               block: { [weak self] in self?.didTapCameraModeButton() })

        let width: CGFloat = 44
        button.autoSetDimensions(to: CGSize(width: width, height: width))
        button.layer.cornerRadius = width / 2
        button.imageEdgeInsets = UIEdgeInsets(top: 10, left: 10, bottom: 10, right: 10)
        button.backgroundColor = .ows_white

        return button
    }()

    private lazy var mediaLibraryModeButton: UIButton = {
        let button = OWSButton(imageName: "actionsheet_camera_roll_black",
                               tintColor: .ows_gray60,
                               block: { [weak self] in self?.didTapMediaLibraryModeButton() })

        let width: CGFloat = 44
        button.autoSetDimensions(to: CGSize(width: width, height: width))
        button.layer.cornerRadius = width / 2
        button.imageEdgeInsets = UIEdgeInsets(top: 10, left: 10, bottom: 10, right: 10)
        button.backgroundColor = .ows_white

        return button
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
        let approvalViewController = AttachmentApprovalViewController(mode: .sharedNavigation, attachments: self.attachments)
        approvalViewController.approvalDelegate = self

        pushViewController(approvalViewController, animated: true)
        updateButtons()
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
}

extension SendMediaNavigationController: PhotoCaptureViewControllerDelegate {
    func photoCaptureViewController(_ photoCaptureViewController: PhotoCaptureViewController, didFinishProcessingAttachment attachment: SignalAttachment) {
        attachmentDraftCollection.append(.camera(attachment: attachment))
        if isInBatchSelectMode {
            updateButtons()
        } else {
            pushApprovalViewController()
        }
    }

    func photoCaptureViewControllerDidCancel(_ photoCaptureViewController: PhotoCaptureViewController) {
        self.sendMediaNavDelegate?.sendMediaNavDidCancel(self)
    }
}

extension SendMediaNavigationController: ImagePickerGridControllerDelegate {

    func imagePickerDidCompleteSelection(_ imagePicker: ImagePickerGridController) {
        showApprovalAfterProcessingAnyMediaLibrarySelections()
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

        updateButtons()
    }

    func imagePicker(_ imagePicker: ImagePickerGridController, didDeselectAsset asset: PHAsset) {
        if mediaLibrarySelections.hasValue(forKey: asset) {
            mediaLibrarySelections.remove(key: asset)

            updateButtons()
        }
    }

    func imagePickerCanSelectAdditionalItems(_ imagePicker: ImagePickerGridController) -> Bool {
        return attachmentDraftCollection.count <= SignalAttachment.maxAttachmentsAllowed
    }
}

extension SendMediaNavigationController: AttachmentApprovalViewControllerDelegate {
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

        popViewController(animated: true) {
            self.updateButtons()
        }
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

    // MARK -

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
