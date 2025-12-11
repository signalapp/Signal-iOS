//
// Copyright 2019 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
import SignalServiceKit

public class AttachmentApprovalItem {

    enum AttachmentApprovalItemError: Error {
        case noThumbnail
    }

    public let attachment: PreviewableAttachment

    enum `Type` {
        case generic
        case image
        case video
    }

    var type: `Type` {
        if imageEditorModel != nil {
            return .image
        }
        if videoEditorModel != nil {
            return .video
        }
        return .generic
    }

    // This might be nil if the attachment is not a valid image.
    let imageEditorModel: ImageEditorModel?
    // This might be nil if the attachment is not a valid video.
    let videoEditorModel: VideoEditorModel?
    let canSave: Bool

    public init(attachment: PreviewableAttachment, canSave: Bool) {
        self.attachment = attachment
        self.canSave = canSave

        self.imageEditorModel = AttachmentApprovalItem.imageEditorModel(for: attachment)
        if self.imageEditorModel == nil {
            self.videoEditorModel = AttachmentApprovalItem.videoEditorModel(for: attachment)
        } else {
            // Make sure we only have one of a video editor and an image editor, not both.
            self.videoEditorModel = nil
        }
    }

    private static func imageEditorModel(for attachment: PreviewableAttachment) -> ImageEditorModel? {
        guard attachment.rawValue.isImage, !attachment.rawValue.isAnimatedImage else {
            return nil
        }
        do {
            return try ImageEditorModel(srcImagePath: attachment.rawValue.dataSource.fileUrl.path)
        } catch {
            owsFailDebug("Could not create image editor: \(error)")
            return nil
        }
    }

    private static func videoEditorModel(for attachment: PreviewableAttachment) -> VideoEditorModel? {
        do {
            return try VideoEditorModel(attachment)
        } catch {
            owsFailDebug("couldn't create video editor: \(error)")
            return nil
        }
    }

    func getThumbnailImage() -> UIImage? {
        return self.attachment.rawValue.staticThumbnail()
    }

    public func isIdenticalTo(_ other: AttachmentApprovalItem?) -> Bool {
        return self === other
    }
}

// MARK: -

class AttachmentApprovalItemCollection {
    private(set) var attachmentApprovalItems: [AttachmentApprovalItem]
    let isAddMoreVisible: () -> Bool

    init(attachmentApprovalItems: [AttachmentApprovalItem], isAddMoreVisible: @escaping () -> Bool) {
        self.attachmentApprovalItems = attachmentApprovalItems
        self.isAddMoreVisible = isAddMoreVisible
    }

    func itemAfter(item: AttachmentApprovalItem) -> AttachmentApprovalItem? {
        guard let currentIndex = attachmentApprovalItems.firstIndex(where: { $0.isIdenticalTo(item) }) else {
            owsFailDebug("currentIndex was unexpectedly nil")
            return nil
        }

        let nextIndex = attachmentApprovalItems.index(after: currentIndex)

        return attachmentApprovalItems[safe: nextIndex]
    }

    func itemBefore(item: AttachmentApprovalItem) -> AttachmentApprovalItem? {
        guard let currentIndex = attachmentApprovalItems.firstIndex(where: { $0.isIdenticalTo(item) }) else {
            owsFailDebug("currentIndex was unexpectedly nil")
            return nil
        }

        let prevIndex = attachmentApprovalItems.index(before: currentIndex)

        return attachmentApprovalItems[safe: prevIndex]
    }

    func remove(item: AttachmentApprovalItem) {
        attachmentApprovalItems.removeAll(where: { $0.isIdenticalTo(item) })
    }

    var count: Int {
        return attachmentApprovalItems.count
    }
}
