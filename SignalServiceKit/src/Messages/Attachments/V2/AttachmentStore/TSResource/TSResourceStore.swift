//
// Copyright 2024 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation

public protocol TSResourceStore {

    func fetch(
        _ ids: [TSResourceId],
        tx: DBReadTransaction
    ) -> [TSResource]

    // MARK: - Message Attachment fetching

    /// Includes all types: media, long text, voice message, stickers,
    /// quoted reply thumbnails, link preview images, contact avatars.
    func allAttachments(
        for message: TSMessage,
        tx: DBReadTransaction
    ) -> [TSResourceReference]

    /// Includes media, long text, and voice message attachments.
    /// Excludes stickers, quoted reply thumbnails, link preview images, contact avatars.
    func bodyAttachments(
        for message: TSMessage,
        tx: DBReadTransaction
    ) -> [TSResourceReference]

    /// Includes media and voice message attachments.
    /// Excludes long text, stickers, quoted reply thumbnails, link preview images, contact avatars.
    func bodyMediaAttachments(
        for message: TSMessage,
        tx: DBReadTransaction
    ) -> [TSResourceReference]

    func oversizeTextAttachment(
        for message: TSMessage,
        tx: DBReadTransaction
    ) -> TSResourceReference?

    func contactShareAvatarAttachment(
        for message: TSMessage,
        tx: DBReadTransaction
    ) -> TSResourceReference?

    func linkPreviewAttachment(
        for message: TSMessage,
        tx: DBReadTransaction
    ) -> TSResourceReference?

    func stickerAttachment(
        for message: TSMessage,
        tx: DBReadTransaction
    ) -> TSResourceReference?

    /// Body attachments are explicitly ordered on a message.
    /// Given an attachment id, return its index in the ordering.
    func indexForBodyAttachmentId(
        _ attachmentId: TSResourceId,
        on message: TSMessage,
        tx: DBReadTransaction
    ) -> Int?

    // MARK: - Quoted Messages

    func quotedAttachmentReference(
        from info: OWSAttachmentInfo,
        parentMessage: TSMessage,
        tx: DBReadTransaction
    ) -> TSQuotedMessageResourceReference?

    func attachmentToUseInQuote(
        originalMessage: TSMessage,
        tx: DBReadTransaction
    ) -> TSResourceReference?
}

// MARK: - Convenience

extension TSResourceStore {

    public func fetch(
        _ id: TSResourceId,
        tx: DBReadTransaction
    ) -> TSResource? {
        return fetch([id], tx: tx).first
    }

    public func quotedAttachmentReference(
        for message: TSMessage,
        tx: DBReadTransaction
    ) -> TSQuotedMessageResourceReference? {
        guard let info = message.quotedMessage?.attachmentInfo() else {
            return nil
        }
        return quotedAttachmentReference(from: info, parentMessage: message, tx: tx)
    }

    public func quotedThumbnailAttachment(
        for message: TSMessage,
        tx: DBReadTransaction
    ) -> TSResourceReference? {
        let ref = self.quotedAttachmentReference(for: message, tx: tx)
        switch ref {
        case .thumbnail(let thumbnail):
            return thumbnail.attachmentRef
        case .stub, nil:
            return nil
        }
    }
}
