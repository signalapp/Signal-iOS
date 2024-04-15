//
// Copyright 2024 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation

#if TESTABLE_BUILD

public class TSResourceStoreMock: TSResourceStore {

    public init() {}

    // TSMessage.rowId -> resource ref
    public var messageResourceReferences = [Int64: [TSResourceReference]]()
    public var resources = [TSResource]()

    public func fetch(_ ids: [TSResourceId], tx: DBReadTransaction) -> [TSResource] {
        return resources.filter { ids.contains($0.resourceId) }
    }

    public func allAttachments(for message: TSMessage, tx: DBReadTransaction) -> [TSResourceReference] {
        guard let rowId = message.sqliteRowId else {
            return []
        }
        return messageResourceReferences[rowId] ?? []
    }

    public func bodyAttachments(for message: TSMessage, tx: DBReadTransaction) -> [TSResourceReference] {
        // TODO: sub-filter based on reference info
        return allAttachments(for: message, tx: tx)
    }

    public func bodyMediaAttachments(for message: TSMessage, tx: DBReadTransaction) -> [TSResourceReference] {
        // TODO: sub-filter based on reference info
        return allAttachments(for: message, tx: tx)
    }

    public func oversizeTextAttachment(for message: TSMessage, tx: DBReadTransaction) -> TSResourceReference? {
        guard let rowId = message.sqliteRowId else {
            return nil
        }
        // TODO: sub-filter based on reference info
        guard let ref = messageResourceReferences[rowId]?.first else {
            return nil
        }
        return ref
    }

    public func contactShareAvatarAttachment(for message: TSMessage, tx: DBReadTransaction) -> TSResourceReference? {
        // TODO
        return nil
    }

    public func linkPreviewAttachment(for message: TSMessage, tx: DBReadTransaction) -> TSResourceReference? {
        // TODO
        return nil
    }

    public func stickerAttachment(for message: TSMessage, tx: DBReadTransaction) -> TSResourceReference? {
        // TODO
        return nil
    }

    public func quotedAttachmentReference(
        from info: OWSAttachmentInfo,
        parentMessage: TSMessage,
        tx: DBReadTransaction
    ) -> TSQuotedMessageResourceReference? {
        guard let rowId = parentMessage.sqliteRowId else {
            return nil
        }
        // TODO: sub-filter based on reference info
        return messageResourceReferences[rowId]?
            .first
            .map { .thumbnail($0) }
    }

    public func attachmentToUseInQuote(
        originalMessage: TSMessage,
        tx: DBReadTransaction
    ) -> TSResourceReference? {
        return nil
    }

    public func mediaAttachment(
        for storyMessage: StoryMessage,
        tx: DBReadTransaction
    ) -> TSResourceReference? {
        return nil
    }

    public func linkPreviewAttachment(
        for storyMessage: StoryMessage,
        tx: DBReadTransaction
    ) -> TSResourceReference? {
        return nil
    }
}

#endif
