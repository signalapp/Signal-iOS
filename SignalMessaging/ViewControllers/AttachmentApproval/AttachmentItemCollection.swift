//
//  Copyright (c) 2019 Open Whisper Systems. All rights reserved.
//

import Foundation
import PromiseKit

class AddMoreRailItem: GalleryRailItem {
    func buildRailItemView() -> UIView {
        let view = UIView()
        view.backgroundColor = UIColor.black.withAlphaComponent(0.33)

        let iconView = UIImageView(image: #imageLiteral(resourceName: "plus-24").withRenderingMode(.alwaysTemplate))
        iconView.tintColor = .ows_white
        view.addSubview(iconView)
        iconView.setCompressionResistanceHigh()
        iconView.setContentHuggingHigh()
        iconView.autoCenterInSuperview()

        return view
    }
}

extension AddMoreRailItem: Equatable {
    static func == (lhs: AddMoreRailItem, rhs: AddMoreRailItem) -> Bool {
        return true
    }
}

public struct AttachmentApprovalItem: Hashable {

    enum AttachmentApprovalItemError: Error {
        case noThumbnail
    }

    public let attachment: SignalAttachment

    // This might be nil if the attachment is not a valid image.
    let imageEditorModel: ImageEditorModel?
    let canSave: Bool

    public init(attachment: SignalAttachment, canSave: Bool) {
        self.attachment = attachment
        self.canSave = canSave

        // Try and make a ImageEditorModel.
        // This will only apply for valid images.
        if attachment.isValidImage,
            !attachment.isAnimatedImage,
            let dataUrl: URL = attachment.dataUrl,
            dataUrl.isFileURL {

            let path = dataUrl.path
            do {
                imageEditorModel = try ImageEditorModel(srcImagePath: path)
            } catch {
                owsFailDebug("Could not create image editor: \(error)")
                imageEditorModel = nil
            }
        } else {
            imageEditorModel = nil
        }
    }

    // MARK: 

    var captionText: String? {
        return attachment.captionText
    }

    func getThumbnailImage() -> UIImage? {
        return self.attachment.staticThumbnail()
    }

    // MARK: Hashable

    public func hash(into hasher: inout Hasher) {
        return hasher.combine(attachment)
    }

    // MARK: Equatable

    public static func == (lhs: AttachmentApprovalItem, rhs: AttachmentApprovalItem) -> Bool {
        return lhs.attachment == rhs.attachment
    }
}

// MARK: -

class AttachmentApprovalItemCollection {
    private (set) var attachmentApprovalItems: [AttachmentApprovalItem]
    let isAddMoreVisible: () -> Bool

    init(attachmentApprovalItems: [AttachmentApprovalItem], isAddMoreVisible: @escaping () -> Bool) {
        self.attachmentApprovalItems = attachmentApprovalItems
        self.isAddMoreVisible = isAddMoreVisible
    }

    func itemAfter(item: AttachmentApprovalItem) -> AttachmentApprovalItem? {
        guard let currentIndex = attachmentApprovalItems.firstIndex(of: item) else {
            owsFailDebug("currentIndex was unexpectedly nil")
            return nil
        }

        let nextIndex = attachmentApprovalItems.index(after: currentIndex)

        return attachmentApprovalItems[safe: nextIndex]
    }

    func itemBefore(item: AttachmentApprovalItem) -> AttachmentApprovalItem? {
        guard let currentIndex = attachmentApprovalItems.firstIndex(of: item) else {
            owsFailDebug("currentIndex was unexpectedly nil")
            return nil
        }

        let prevIndex = attachmentApprovalItems.index(before: currentIndex)

        return attachmentApprovalItems[safe: prevIndex]
    }

    func remove(item: AttachmentApprovalItem) {
        attachmentApprovalItems = attachmentApprovalItems.filter { $0 != item }
    }

    var count: Int {
        return attachmentApprovalItems.count
    }
}
