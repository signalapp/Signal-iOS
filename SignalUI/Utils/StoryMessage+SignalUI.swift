//
// Copyright 2022 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import SignalServiceKit

extension StoryMessage {

    func quotedBody(transaction: SDSAnyReadTransaction) -> MessageBody? {
        let caption: String?
        let captionStyles: [NSRangedValue<MessageBodyRanges.CollapsedStyle>]
        switch attachment {
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

        case .file(let file):
            guard let attachment = TSAttachment.anyFetch(uniqueId: file.attachmentId, transaction: transaction) else {
                owsFailDebug("Missing attachment for story message \(timestamp)")
                return nil
            }
            caption = attachment.caption(forContainingStoryMessage: self, transaction: transaction)
            captionStyles = file.captionStyles
        case .foreignReferenceAttachment:
            guard let resource = StoryMessageResource.fetch(storyMessage: self, tx: transaction) else {
                owsFailDebug("Missing attachment for story message \(timestamp)")
                return nil
            }
            caption = resource.caption
            captionStyles = resource.captionStyles
        }

        guard let caption else {
            return nil
        }
        // Note: stripping any over-extended styles to the caption
        // length will happen at hydration time, which is required
        // to turn a MessageBody into something we can display.
        return MessageBody(
            text: caption,
            ranges: MessageBodyRanges(mentions: [:], orderedMentions: [], collapsedStyles: captionStyles)
        )
    }

    func thumbnailImage(transaction: SDSAnyReadTransaction) -> UIImage? {
        switch attachment {
        case .text:
            return nil
        case .file, .foreignReferenceAttachment:
            guard let attachment = self.fileAttachment(tx: transaction) else {
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
