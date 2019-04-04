//
//  Copyright (c) 2019 Open Whisper Systems. All rights reserved.
//

import Foundation
import PromiseKit

class SignalAttachmentItem: Hashable {

    enum SignalAttachmentItemError: Error {
        case noThumbnail
    }

    let attachment: SignalAttachment

    // This might be nil if the attachment is not a valid image.
    var imageEditorModel: ImageEditorModel?

    init(attachment: SignalAttachment) {
        self.attachment = attachment

        // Try and make a ImageEditorModel.
        // This will only apply for valid images.
        if ImageEditorModel.isFeatureEnabled,
            let dataUrl: URL = attachment.dataUrl,
            dataUrl.isFileURL {
            let path = dataUrl.path
            do {
                imageEditorModel = try ImageEditorModel(srcImagePath: path)
            } catch {
                // Usually not an error; this usually indicates invalid input.
                Logger.warn("Could not create image editor: \(error)")
            }
        }
    }

    // MARK: 

    var captionText: String? {
        return attachment.captionText
    }

    var imageSize: CGSize = .zero

    func getThumbnailImage() -> Promise<UIImage> {
        return DispatchQueue.global().async(.promise) { () -> UIImage in
            guard let image = self.attachment.staticThumbnail() else {
                throw SignalAttachmentItemError.noThumbnail
            }
            return image
            }.tap { result in
                switch result {
                case .fulfilled(let image):
                    self.imageSize = image.size
                case .rejected(let error):
                    owsFailDebug("failed with error: \(error)")
                }
        }
    }

    // MARK: Hashable

    public var hashValue: Int {
        return attachment.hashValue
    }

    // MARK: Equatable

    static func == (lhs: SignalAttachmentItem, rhs: SignalAttachmentItem) -> Bool {
        return lhs.attachment == rhs.attachment
    }
}

// MARK: -

class AttachmentItemCollection {
    private (set) var attachmentItems: [SignalAttachmentItem]
    init(attachmentItems: [SignalAttachmentItem]) {
        self.attachmentItems = attachmentItems
    }

    func itemAfter(item: SignalAttachmentItem) -> SignalAttachmentItem? {
        guard let currentIndex = attachmentItems.firstIndex(of: item) else {
            owsFailDebug("currentIndex was unexpectedly nil")
            return nil
        }

        let nextIndex = attachmentItems.index(after: currentIndex)

        return attachmentItems[safe: nextIndex]
    }

    func itemBefore(item: SignalAttachmentItem) -> SignalAttachmentItem? {
        guard let currentIndex = attachmentItems.firstIndex(of: item) else {
            owsFailDebug("currentIndex was unexpectedly nil")
            return nil
        }

        let prevIndex = attachmentItems.index(before: currentIndex)

        return attachmentItems[safe: prevIndex]
    }

    func remove(item: SignalAttachmentItem) {
        attachmentItems = attachmentItems.filter { $0 != item }
    }

    var count: Int {
        return attachmentItems.count
    }
}
