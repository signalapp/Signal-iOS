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

    // MARK: -

    @objc
    public weak var sendMediaNavDelegate: SendMediaNavDelegate?

    @objc
    public class func showingCameraFirst() -> SendMediaNavigationController {
        let navController = SendMediaNavigationController()

        if let owsNavBar = navController.navigationBar as? OWSNavigationBar {
            owsNavBar.overrideTheme(type: .clear)
        } else {
            owsFailDebug("unexpected navbar: \(navController.navigationBar)")
        }
        navController.setViewControllers([navController.captureViewController], animated: false)

        return navController
    }

    @objc
    public class func showingMediaLibraryFirst() -> SendMediaNavigationController {
        let navController = SendMediaNavigationController()

        if let owsNavBar = navController.navigationBar as? OWSNavigationBar {
            owsNavBar.overrideTheme(type: .clear)
        } else {
            owsFailDebug("unexpected navbar: \(navController.navigationBar)")
        }
        navController.setViewControllers([navController.mediaLibraryViewController], animated: false)

        return navController
    }

    // MARK: 

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
    }
}

extension SendMediaNavigationController: PhotoCaptureViewControllerDelegate {
    func photoCaptureViewController(_ photoCaptureViewController: PhotoCaptureViewController, didFinishProcessingAttachment attachment: SignalAttachment) {
        attachmentDraftCollection.append(.camera(attachment: attachment))

        pushApprovalViewController()
    }

    func photoCaptureViewControllerDidCancel(_ photoCaptureViewController: PhotoCaptureViewController) {
        // TODO
        // sometimes we might want this to be a "back" to the approval view
        // other times we might want this to be a "close" and take me back to the CVC
        // seems like we should show the "back" and have a seprate "didTapBack" delegate method or something...

        self.sendMediaNavDelegate?.sendMediaNavDidCancel(self)
    }
}

extension SendMediaNavigationController: ImagePickerGridControllerDelegate {

    func imagePickerDidCompleteSelection(_ imagePicker: ImagePickerGridController) {
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
    }

    func imagePicker(_ imagePicker: ImagePickerGridController, didDeselectAsset asset: PHAsset) {
        if mediaLibrarySelections.hasValue(forKey: asset) {
            mediaLibrarySelections.remove(key: asset)
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
        mediaLibraryViewController.isInBatchSelectMode = true
        mediaLibraryViewController.collectionView?.reloadData()

        popViewController(animated: true)
    }
}

enum AttachmentDraft {
    case camera(attachment: SignalAttachment)
    case picker(attachment: MediaLibraryAttachment)
}

extension AttachmentDraft {
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

struct AttachmentDraftCollection {
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

struct MediaLibrarySelection: Hashable, Equatable {
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

struct MediaLibraryAttachment: Hashable, Equatable {
    let asset: PHAsset
    let signalAttachment: SignalAttachment

    public var hashValue: Int {
        return asset.hashValue
    }

    public static func == (lhs: MediaLibraryAttachment, rhs: MediaLibraryAttachment) -> Bool {
        return lhs.asset == rhs.asset
    }
}
