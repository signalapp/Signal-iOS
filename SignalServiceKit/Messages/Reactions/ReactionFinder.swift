//
// Copyright 2019 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
import GRDB
public import LibSignalClient

// MARK: -

public struct ReactionFinder {

    public let messageId: ReactionRecord.InteractionId

    public init(messageId: ReactionRecord.InteractionId) {
        self.messageId = messageId
    }

    private func baseQuery() -> QueryInterfaceRequest<ReactionRecord> {
        return ReactionRecord.filter(ReactionRecord.Columns.messageId == self.messageId)
    }

    /// Returns the given users reaction if it exists, otherwise nil
    public func reaction(
        for aci: Aci,
        recipientStore: RecipientDatabaseTable = DependenciesBridge.shared.recipientDatabaseTable,
        tx: DBReadTransaction,
    ) -> ReactionRecord? {
        // If there's no recipient, there can't be any reactions.
        guard let recipient = recipientStore.fetchRecipient(serviceId: aci, transaction: tx) else {
            return nil
        }
        return reaction(for: recipient.id, tx: tx)
    }

    public func reaction(for reactorId: SignalRecipient.RowId, tx: DBReadTransaction) -> ReactionRecord? {
        let query = baseQuery().filter(ReactionRecord.Columns.reactorId == reactorId)
        return failIfThrows { try query.fetchOne(tx.database) }
    }

    /// Returns an ordered list of all reactions to this message
    public func allReactions(tx: DBReadTransaction) -> [ReactionRecord] {
        let query = baseQuery().order(ReactionRecord.Columns.id.desc)
        return failIfThrows { try query.fetchAll(tx.database) }
    }

    /// Returns a list of reactions to this message that have yet to be read
    public func fetchUnreadReactions(
        inThreadId threadId: TSThread.RowId,
        tx: DBReadTransaction,
    ) -> [ReactionRecord] {
        let query = baseQuery()
            .filter(ReactionRecord.Columns.threadId == threadId)
            .filter(ReactionRecord.Columns.isRead == false)
        return failIfThrows { try query.fetchAll(tx.database) }
    }

    static func fetchNextUnreadReaction(
        inThreadId threadId: ReactionRecord.ThreadId,
        upThroughMessageId messageId: ReactionRecord.InteractionId,
        tx: DBReadTransaction,
    ) -> ReactionRecord? {
        let query = ReactionRecord
            .filter(ReactionRecord.Columns.threadId == threadId)
            .filter(ReactionRecord.Columns.messageId <= messageId)
            .filter(ReactionRecord.Columns.isRead == false)
            .order(ReactionRecord.Columns.messageId.asc, ReactionRecord.Columns.id.asc)
        return failIfThrows { try query.fetchOne(tx.database) }
    }

    /// Delete all reaction records associated with this message
    public func deleteAllReactions(tx: DBWriteTransaction) {
        let query = baseQuery()
        failIfThrows { try query.deleteAll(tx.database) }
    }

    static func fetchReactions(
        forReactorId reactorId: ReactionRecord.RecipientId,
        tx: DBReadTransaction,
    ) -> [ReactionRecord] {
        let query = ReactionRecord.filter(ReactionRecord.Columns.reactorId == reactorId)
        return failIfThrows { try query.fetchAll(tx.database) }
    }
}
