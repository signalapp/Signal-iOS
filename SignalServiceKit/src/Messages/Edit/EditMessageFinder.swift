//
// Copyright 2023 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
import GRDB

public class EditMessageFinder {
    public static func editTarget(
        timestamp: UInt64,
        author: SignalServiceAddress,
        tx: DBReadTransaction
    ) -> TSInteraction? {

        let arguments: StatementArguments
        let authorClause: String

        if author.isLocalAddress {
            authorClause = "AND \(interactionColumn: .authorUUID) IS NULL"
            arguments = [timestamp]
        } else if let authorUuid = author.uuid?.uuidString {
            authorClause = "AND \(interactionColumn: .authorUUID) = ?"
            arguments = [timestamp, authorUuid]
        } else {
            return nil
        }

        let sql = """
            SELECT *
            FROM \(InteractionRecord.databaseTableName)
            WHERE \(interactionColumn: .timestamp) = ?
            \(authorClause)
            LIMIT 1
        """

        let val = TSInteraction.grdbFetchOne(
            sql: sql,
            arguments: arguments,
            transaction: SDSDB.shimOnlyBridge(tx).unwrapGrdbRead
        )

        return val
    }

    public class func findMessage(
        fromEdit edit: TSMessage,
        transaction: SDSAnyReadTransaction
    ) -> TSMessage? {

        let sql = """
                SELECT * FROM \(InteractionRecord.databaseTableName) AS interaction
                INNER JOIN \(EditRecord.databaseTableName) AS editRecord
                ON interaction.\(interactionColumn: .id) = editRecord.latestRevisionId
                WHERE editRecord.pastRevisionId = ?
                LIMIT 1
            """

        let arguments: StatementArguments = [edit.grdbId]
        return TSMessage.grdbFetchOne(
            sql: sql,
            arguments: arguments,
            transaction: transaction.unwrapGrdbRead
        ) as? TSMessage
    }

    public static func numberOfEdits(
        for message: TSMessage,
        transaction: SDSAnyReadTransaction
    ) -> Int {

        let sql = """
                SELECT COUNT(*)
                FROM \(EditRecord.databaseTableName)
                WHERE editRecord.latestRevisionId = ?
            """

        let arguments: StatementArguments = [message.grdbId]

        return try! Int.fetchOne(
            transaction.unwrapGrdbRead.database,
            sql: sql,
            arguments: arguments
        ) ?? 0
    }

}
