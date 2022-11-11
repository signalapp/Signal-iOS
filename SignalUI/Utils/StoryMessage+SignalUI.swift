//
// Copyright 2022 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation

extension StoryMessage {

    @objc
    func quotedBody(transaction: SDSAnyReadTransaction) -> String? {
        switch attachment {
        case .file(let attachmentId):
            guard let attachment = TSAttachment.anyFetch(uniqueId: attachmentId, transaction: transaction) else {
                owsFailDebug("Missing attachment for story message \(timestamp)")
                return nil
            }
            return attachment.caption
        case .text(let attachment):
            return attachment.text ?? attachment.preview?.urlString
        }
    }

    @objc
    func quotedAttachment(transaction: SDSAnyReadTransaction) -> TSAttachment? {
        guard case .file(let attachmentId) = attachment else { return nil }
        guard let attachment = TSAttachment.anyFetch(uniqueId: attachmentId, transaction: transaction) else {
            owsFailDebug("Missing attachment for story message \(timestamp)")
            return nil
        }
        return attachment
    }

    @objc
    func thumbnailImage(transaction: SDSAnyReadTransaction) -> UIImage? {
        guard case .file(let attachmentId) = attachment else { return nil }

        guard let attachment = TSAttachment.anyFetch(uniqueId: attachmentId, transaction: transaction) else {
            owsFailDebug("Missing attachment for story message \(timestamp)")
            return nil
        }
        if let stream = attachment as? TSAttachmentStream {
            return stream.thumbnailImageSmallSync()
        } else if let blurHash = attachment.blurHash {
            return BlurHash.image(for: blurHash)
        } else {
            return nil
        }
    }

    @objc
    func thumbnailView() -> UIView? {
        guard case .text(let attachment) = attachment else { return nil }
        return TextAttachmentView(attachment: attachment).asThumbnailView()
    }
}
