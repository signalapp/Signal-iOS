//
// Copyright 2023 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
import LibSignalClient

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

    /// Create a new reaction from a backup.
    func createReactionFromRestoredBackup(
        uniqueMessageId: String,
        emoji: String,
        reactorAci: Aci,
        sentAtTimestamp: UInt64,
        sortOrder: UInt64,
        tx: DBWriteTransaction
    )
    func createReactionFromRestoredBackup(
        uniqueMessageId: String,
        emoji: String,
        reactorE164: E164,
        sentAtTimestamp: UInt64,
        sortOrder: UInt64,
        tx: DBWriteTransaction
    )

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

    public func createReactionFromRestoredBackup(
        uniqueMessageId: String,
        emoji: String,
        reactorAci: Aci,
        sentAtTimestamp: UInt64,
        sortOrder: UInt64,
        tx: DBWriteTransaction
    ) {
        OWSReaction.fromRestoredBackup(
            uniqueMessageId: uniqueMessageId,
            emoji: emoji,
            reactorAci: reactorAci,
            sentAtTimestamp: sentAtTimestamp,
            sortOrder: sortOrder
        ).anyInsert(transaction: SDSDB.shimOnlyBridge(tx))
    }

    public func createReactionFromRestoredBackup(
        uniqueMessageId: String,
        emoji: String,
        reactorE164: E164,
        sentAtTimestamp: UInt64,
        sortOrder: UInt64,
        tx: DBWriteTransaction
    ) {
        OWSReaction.fromRestoredBackup(
            uniqueMessageId: uniqueMessageId,
            emoji: emoji,
            reactorE164: reactorE164,
            sentAtTimestamp: sentAtTimestamp,
            sortOrder: sortOrder
        ).anyInsert(transaction: SDSDB.shimOnlyBridge(tx))
    }

    public func deleteAllReactions(messageId: MessageId, tx: DBWriteTransaction) {
        ReactionFinder(uniqueMessageId: messageId)
            .deleteAllReactions(transaction: SDSDB.shimOnlyBridge(tx).unwrapGrdbWrite)
    }
}

#if TESTABLE_BUILD

open class MockReactionStore: ReactionStore {

    public var reactions = [OWSReaction]()

    public func reaction(
        for aci: Aci,
        messageId: MessageId,
        tx: DBReadTransaction
    ) -> OWSReaction? {
        return reactions.first(where: { $0.uniqueMessageId == messageId && $0.reactorAci == aci })
    }

    public func allReactions(messageId: MessageId, tx: DBReadTransaction) -> [OWSReaction] {
        return reactions.filter { $0.uniqueMessageId == messageId }
    }

    public func unreadReactions(messageId: MessageId, tx: DBReadTransaction) -> [OWSReaction] {
        return reactions.filter { $0.uniqueMessageId == messageId && $0.read.negated }
    }

    public func allUniqueIds(messageId: MessageId, tx: DBReadTransaction) -> [String] {
        return reactions.compactMap { $0.uniqueMessageId == messageId ? $0.uniqueId : nil }
    }

    public func createReactionFromRestoredBackup(
        uniqueMessageId: String,
        emoji: String,
        reactorAci: Aci,
        sentAtTimestamp: UInt64,
        sortOrder: UInt64,
        tx: DBWriteTransaction
    ) {
        reactions.append(OWSReaction.fromRestoredBackup(
            uniqueMessageId: uniqueMessageId,
            emoji: emoji,
            reactorAci: reactorAci,
            sentAtTimestamp: sentAtTimestamp,
            sortOrder: sortOrder
        ))
    }

    public func createReactionFromRestoredBackup(
        uniqueMessageId: String,
        emoji: String,
        reactorE164: E164,
        sentAtTimestamp: UInt64,
        sortOrder: UInt64,
        tx: DBWriteTransaction
    ) {
        reactions.append(OWSReaction.fromRestoredBackup(
            uniqueMessageId: uniqueMessageId,
            emoji: emoji,
            reactorE164: reactorE164,
            sentAtTimestamp: sentAtTimestamp,
            sortOrder: sortOrder
        ))
    }

    public func deleteAllReactions(messageId: MessageId, tx: DBWriteTransaction) {
        return reactions = reactions.filter { $0.uniqueMessageId != messageId }
    }
}

#endif
