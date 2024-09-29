//
// Copyright 2024 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

public import SignalServiceKit

extension TSMessage {

    /// Dangerous to use for uninserted messages; exposed only in the Signal target because most rendering
    /// uses already-inserted messages, obviating the concern.
    public func hasRenderableContent(tx: SDSAnyReadTransaction) -> Bool {
        guard let rowId = self.sqliteRowId else {
            owsFailDebug("Checking renderable content for uninserted message!")
            return TSMessageBuilder.hasRenderableContent(
                hasNonemptyBody: body?.nilIfEmpty != nil,
                hasBodyAttachmentsOrOversizeText: false,
                hasLinkPreview: linkPreview != nil,
                hasQuotedReply: quotedMessage != nil,
                hasContactShare: contactShare != nil,
                hasSticker: messageSticker != nil,
                hasGiftBadge: giftBadge != nil,
                isStoryReply: isStoryReply,
                isPaymentMessage: (self is OWSPaymentMessage || self is OWSArchivedPaymentMessage),
                storyReactionEmoji: storyReactionEmoji
            )
        }
        return insertedMessageHasRenderableContent(rowId: rowId, tx: tx)
    }
}
