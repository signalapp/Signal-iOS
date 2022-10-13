//
// Copyright 2019 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
import GRDB

// MARK: -

@objc
public class ReactionFinder: NSObject {

    @objc
    public let uniqueMessageId: String

    @objc
    public init(uniqueMessageId: String) {
        self.uniqueMessageId = uniqueMessageId
    }

    /// Returns the given users reaction if it exists, otherwise nil
    @objc
    public func reaction(for reactor: SignalServiceAddress, transaction: GRDBReadTransaction) -> OWSReaction? {
        if let reaction = reactionForUUID(reactor.uuid, transaction: transaction) {
            return reaction
        } else if let reaction = reactionForE164(reactor.phoneNumber, transaction: transaction) {
            return reaction
        } else {
            return nil
        }
    }

    private func reactionForUUID(_ uuid: UUID?, transaction: GRDBReadTransaction) -> OWSReaction? {
        guard let uuidString = uuid?.uuidString else { return nil }
        let sql = """
            SELECT * FROM \(OWSReaction.databaseTableName)
            WHERE \(OWSReaction.columnName(.uniqueMessageId)) = ?
            AND \(OWSReaction.columnName(.reactorUUID)) = ?
        """
        do {
            return try OWSReaction.fetchOne(transaction.database, sql: sql, arguments: [uniqueMessageId, uuidString])
        } catch {
            owsFailDebug("Failed to fetch reaction \(error)")
            return nil
        }
    }

    private func reactionForE164(_ e164: String?, transaction: GRDBReadTransaction) -> OWSReaction? {
        guard let e164 = e164 else { return nil }
        let sql = """
            SELECT * FROM \(OWSReaction.databaseTableName)
            WHERE \(OWSReaction.columnName(.uniqueMessageId)) = ?
            AND \(OWSReaction.columnName(.reactorE164)) = ?
        """
        do {
            return try OWSReaction.fetchOne(transaction.database, sql: sql, arguments: [uniqueMessageId, e164])
        } catch {
            owsFailDebug("Failed to fetch reaction \(error)")
            return nil
        }
    }

    /// Returns a list of all reactions to this message
    @objc
    public func allReactions(transaction: GRDBReadTransaction) -> [OWSReaction] {
        let sql = """
            SELECT * FROM \(OWSReaction.databaseTableName)
            WHERE \(OWSReaction.columnName(.uniqueMessageId)) = ?
            ORDER BY \(OWSReaction.columnName(.id)) DESC
        """

        var reactions = [OWSReaction]()

        do {
            let cursor = try OWSReaction.fetchCursor(transaction.database, sql: sql, arguments: [uniqueMessageId])
            while let reaction = try cursor.next() {
                reactions.append(reaction)
            }
        } catch {
            owsFailDebug("unexpected error \(error)")
        }

        return reactions
    }

    /// Returns a list of reactions to this message that have yet to be read
    @objc
    public func unreadReactions(transaction: GRDBReadTransaction) -> [OWSReaction] {
        let sql = """
            SELECT * FROM \(OWSReaction.databaseTableName)
            WHERE \(OWSReaction.columnName(.uniqueMessageId)) = ?
            AND \(OWSReaction.columnName(.read)) IS 0
            ORDER BY \(OWSReaction.columnName(.id)) DESC
        """

        var reactions = [OWSReaction]()

        do {
            let cursor = try OWSReaction.fetchCursor(transaction.database, sql: sql, arguments: [uniqueMessageId])
            while let reaction = try cursor.next() {
                reactions.append(reaction)
            }
        } catch {
            owsFailDebug("unexpected error \(error)")
        }

        return reactions
    }

    /// A list of all the unique reaction IDs linked to this message, ordered by creation from oldest to neweset
    @objc
    public func allUniqueIds(transaction: GRDBReadTransaction) -> [String] {
        let sql = """
            SELECT \(OWSReaction.columnName(.uniqueId))
            FROM \(OWSReaction.databaseTableName)
            WHERE \(OWSReaction.columnName(.uniqueMessageId)) = ?
        """
        let sqlRequest = SQLRequest<Void>(sql: sql, arguments: [uniqueMessageId], cached: true)

        do {
            let rows = try Row.fetchAll(transaction.database, sqlRequest)
            return rows.map { $0[0] }
        } catch {
            owsFailDebug("unexpected error \(error)")
            return []
        }
    }

    /// Delete all reaction records associated with this message
    @objc
    public func deleteAllReactions(transaction: GRDBWriteTransaction) {
        let sql = """
            DELETE FROM \(OWSReaction.databaseTableName)
            WHERE \(OWSReaction.columnName(.uniqueMessageId)) = ?
        """
        transaction.executeUpdate(sql: sql, arguments: [uniqueMessageId])
    }
}
