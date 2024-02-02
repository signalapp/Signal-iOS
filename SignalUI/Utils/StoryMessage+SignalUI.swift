//
// Copyright 2022 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import SignalServiceKit

extension StoryMessage {

    func quotedBody(transaction: SDSAnyReadTransaction) -> MessageBody? {
        switch attachment {
        case .file(let file):
            guard let attachment = TSAttachment.anyFetch(uniqueId: file.attachmentId, transaction: transaction) else {
                owsFailDebug("Missing attachment for story message \(timestamp)")
                return nil
            }
            guard let caption = attachment.caption(forContainingStoryMessage: self, transaction: transaction) else {
                return nil
            }
            // Note: stripping any over-extended styles to the caption
            // length will happen at hydration time, which is required
            // to turn a MessageBody into something we can display.
            return MessageBody(
                text: caption,
                ranges: MessageBodyRanges(mentions: [:], orderedMentions: [], collapsedStyles: file.captionStyles)
            )
        case .text(let attachment):
            switch attachment.textContent {
            case .styledRanges(let body):
                return body.asMessageBody()
            case .styled(let body, _):
                return MessageBody(text: body, ranges: .empty)
            case .empty:
                guard let urlString = attachment.preview?.urlString else {
                    return nil
                }
                return MessageBody(text: urlString, ranges: .empty)
            }
        }
    }

    func quotedAttachment(transaction: SDSAnyReadTransaction) -> TSAttachment? {
        switch attachment {
        case .file(let file):
            guard let attachment = TSAttachment.anyFetch(uniqueId: file.attachmentId, transaction: transaction) else {
                owsFailDebug("Missing attachment for story message \(timestamp)")
                return nil
            }
            return attachment
        case .text:
            return nil
        }
    }

    func thumbnailImage(transaction: SDSAnyReadTransaction) -> UIImage? {
        switch attachment {
        case .text:
            return nil
        case .file(let file):
            guard let attachment = TSAttachment.anyFetch(uniqueId: file.attachmentId, transaction: transaction) else {
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
    }

    func thumbnailView(spoilerState: SpoilerRenderState) -> UIView? {
        guard case .text(let attachment) = attachment else { return nil }
        return TextAttachmentView(
            attachment: attachment,
            interactionIdentifier: .fromStoryMessage(self),
            spoilerState: spoilerState
        ).asThumbnailView()
    }
}
