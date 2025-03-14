//
// Copyright 2024 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

extension AttachmentReference {

    /// Note: this takes an SDS transaction because its a convenience
    /// method that accesses globals. If you want a testable variant
    /// that lets you override the return value, use AttachmentStore.
    public func fetch(tx: DBReadTransaction) -> Attachment? {
        return DependenciesBridge.shared.attachmentStore.fetch(id: self.attachmentRowId, tx: tx)
    }

    public func fetchOwningMessage(tx: DBReadTransaction) -> TSMessage? {
        switch owner {
        case .message(let messageSource):
            return InteractionFinder.fetch(rowId: messageSource.messageRowId, transaction: tx) as? TSMessage
        case .storyMessage, .thread:
            return nil
        }
    }
}

extension Array where Element == AttachmentReference {

    /// Ordering of the return values is not guaranteed.
    ///
    /// Note: this takes an SDS transaction because its a convenience
    /// method that accesses globals. If you want a testable variant
    /// that lets you override the return value, use AttachmentStore.
    public func fetchAll(tx: DBReadTransaction) -> [Attachment] {
        return DependenciesBridge.shared.attachmentStore.fetch(ids: self.map(\.attachmentRowId), tx: tx)
    }
}
