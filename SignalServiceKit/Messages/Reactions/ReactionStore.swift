//
// Copyright 2023 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
public import LibSignalClient

public protocol ReactionStore {

    /// Refers to ``TSInteraction.uniqueId``.
    typealias MessageId = String

    func reaction(
        for aci: Aci,
        messageId: MessageId,
        tx: DBReadTransaction
    ) -> OWSReaction?

    /// Returns a list of all reactions to this message
    func allReactions(
        messageId: MessageId,
        tx: DBReadTransaction
    ) -> [OWSReaction]

    /// Returns a list of reactions to this message that have yet to be read
    func unreadReactions(
        messageId: MessageId,
        tx: DBReadTransaction
    ) -> [OWSReaction]

    /// A list of all the unique reaction IDs linked to this message, ordered by creation from oldest to neweset
    func allUniqueIds(
        messageId: MessageId,
        tx: DBReadTransaction
    ) -> [String]

    /// Delete all reaction records associated with this message
    func deleteAllReactions(
        messageId: MessageId,
        tx: DBWriteTransaction
    )
}

public class ReactionStoreImpl: ReactionStore {
    public func reaction(
        for aci: Aci,
        messageId: MessageId,
        tx: DBReadTransaction
    ) -> OWSReaction? {
        ReactionFinder(uniqueMessageId: messageId)
            .reaction(for: aci, tx: SDSDB.shimOnlyBridge(tx).unwrapGrdbRead)
    }

    public func allReactions(messageId: MessageId, tx: DBReadTransaction) -> [OWSReaction] {
        ReactionFinder(uniqueMessageId: messageId)
            .allReactions(transaction: SDSDB.shimOnlyBridge(tx).unwrapGrdbRead)
    }

    public func unreadReactions(messageId: MessageId, tx: DBReadTransaction) -> [OWSReaction] {
        ReactionFinder(uniqueMessageId: messageId)
            .unreadReactions(transaction: SDSDB.shimOnlyBridge(tx).unwrapGrdbRead)
    }

    public func allUniqueIds(messageId: MessageId, tx: DBReadTransaction) -> [String] {
        ReactionFinder(uniqueMessageId: messageId)
            .allUniqueIds(transaction: SDSDB.shimOnlyBridge(tx).unwrapGrdbRead)
    }

    public func deleteAllReactions(messageId: MessageId, tx: DBWriteTransaction) {
        ReactionFinder(uniqueMessageId: messageId)
            .deleteAllReactions(transaction: SDSDB.shimOnlyBridge(tx).unwrapGrdbWrite)
    }
}
