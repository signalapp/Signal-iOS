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

        guard let authorUuid = author.uuid?.uuidString else {
            return nil
        }

        let sql = """
            SELECT *
            FROM \(InteractionRecord.databaseTableName)
            WHERE \(interactionColumn: .timestamp) = ?
            AND \(interactionColumn: .authorUUID) = ?
            LIMIT 1
        """

        let arguments: StatementArguments = [timestamp, authorUuid]

        let val = TSInteraction.grdbFetchOne(
            sql: sql,
            arguments: arguments,
            transaction: SDSDB.shimOnlyBridge(tx).unwrapGrdbRead
        )

        return val
    }
}
