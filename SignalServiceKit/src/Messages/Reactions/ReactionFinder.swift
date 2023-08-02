//
// Copyright 2019 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
import GRDB
import LibSignalClient
import SignalCoreKit

// MARK: -

public class ReactionFinder {

    public let uniqueMessageId: String

    public init(uniqueMessageId: String) {
        self.uniqueMessageId = uniqueMessageId
    }

    /// Returns the given users reaction if it exists, otherwise nil
    public func reaction(for aci: Aci, tx: GRDBReadTransaction) -> OWSReaction? {
        // If there is a reaction for the ACI, return it.
        do {
            let sql = """
                SELECT * FROM \(OWSReaction.databaseTableName)
                WHERE \(OWSReaction.columnName(.uniqueMessageId)) = ?
                AND \(OWSReaction.columnName(.reactorUUID)) = ?
            """
            let aciString = aci.serviceIdUppercaseString
            if let result = try OWSReaction.fetchOne(tx.database, sql: sql, arguments: [uniqueMessageId, aciString]) {
                return result
            }
        } catch {
            owsFailDebug("Failed to fetch reaction \(error)")
            return nil
        }

        // Otherwise, if there is a reaction for the phone number *without* an ACI,
        // return it. (This handles cases where we saved a reaction before we knew
        // the ACI that was associated with that phone number.)
        guard let phoneNumber = SignalServiceAddress(aci).phoneNumber else {
            return nil
        }
        do {
            let sql = """
                SELECT * FROM \(OWSReaction.databaseTableName)
                WHERE \(OWSReaction.columnName(.uniqueMessageId)) = ?
                AND \(OWSReaction.columnName(.reactorUUID)) IS NULL
                AND \(OWSReaction.columnName(.reactorE164)) = ?
            """
            if let result = try OWSReaction.fetchOne(tx.database, sql: sql, arguments: [uniqueMessageId, phoneNumber]) {
                return result
            }
        } catch {
            owsFailDebug("Failed to fetch reaction \(error)")
            return nil
        }

        return nil
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
        transaction.execute(sql: sql, arguments: [uniqueMessageId])
    }
}
