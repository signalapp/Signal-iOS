//
// Copyright 2019 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
import GRDB

public class LegacyMessageJobFinder {
    func allJobs(transaction: SDSAnyReadTransaction) -> [OWSMessageContentJob] {
        let sql = """
            SELECT *
            FROM \(MessageContentJobRecord.databaseTableName)
            ORDER BY \(messageContentJobColumn: .id)
        """
        let cursor = OWSMessageContentJob.grdbFetchCursor(
            sql: sql,
            transaction: transaction.unwrapGrdbRead
        )

        do {
            return try cursor.all()
        } catch {
            DatabaseCorruptionState.flagDatabaseReadCorruptionIfNecessary(
                userDefaults: CurrentAppContext().appUserDefaults(),
                error: error
            )
            owsFail("Failed to fetch all jobs")
        }
    }
}
