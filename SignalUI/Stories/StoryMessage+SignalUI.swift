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

        case .media:
            guard
                let rowId = self.id,
                let attachmentPointer = DependenciesBridge.shared.attachmentStore.fetchFirstReference(
                    owner: .storyMessageMedia(storyMessageRowId: rowId),
                    tx: transaction.asV2Read
                )
            else {
                owsFailDebug("Missing attachment for story message \(timestamp)")
                return nil
            }
            let styledCaption = attachmentPointer.storyMediaCaption
            caption = styledCaption?.text
            captionStyles = styledCaption?.collapsedStyles ?? []
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
}
