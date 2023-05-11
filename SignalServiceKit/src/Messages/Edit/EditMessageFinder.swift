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
}
