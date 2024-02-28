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

    public func fetch(_ id: TSResourceId, tx: DBReadTransaction) -> TSResource? {
        return resources.first(where: { $0.resourceId == id })
    }

    public func fetch(_ ids: [TSResourceId], tx: DBReadTransaction) -> [TSResource] {
        return resources.filter { ids.contains($0.resourceId) }
    }

    public func allAttachments(for message: TSMessage, tx: DBReadTransaction) -> TSResourceReferences {
        guard let rowId = message.sqliteRowId else {
            return .empty
        }
        let refs = messageResourceReferences[rowId] ?? []
        return .init(ids: refs.map(\.id), fetcher: { innerTx in
            return self.fetch(refs.map(\.id), tx: innerTx)
        })
    }

    public func bodyAttachments(for message: TSMessage, tx: DBReadTransaction) -> TSResourceReferences {
        // TODO: sub-filter based on reference info
        return allAttachments(for: message, tx: tx)
    }

    public func bodyMediaAttachments(for message: TSMessage, tx: DBReadTransaction) -> TSResourceReferences {
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

    public func quotedMessageThumbnailAttachment(for message: TSMessage, tx: DBReadTransaction) -> TSResourceReference? {
        // TODO
        return nil
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

    public func indexForBodyAttachmentId(_ attachmentId: TSResourceId, on message: TSMessage, tx: DBReadTransaction) -> Int? {
        guard let rowId = message.sqliteRowId else {
            return nil
        }
        let refs = messageResourceReferences[rowId] ?? []
        return refs.firstIndex(where: { $0.id == attachmentId })
    }
}

#endif
