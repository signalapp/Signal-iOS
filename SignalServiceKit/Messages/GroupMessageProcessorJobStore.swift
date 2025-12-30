//
// Copyright 2025 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
import GRDB

struct GroupMessageProcessorJobStore {
    func allEnqueuedGroupIds(tx: DBReadTransaction) -> [Data] {
        let sql = """
        SELECT DISTINCT \(GroupMessageProcessorJob.CodingKeys.groupId.rawValue)
        FROM \(GroupMessageProcessorJob.databaseTableName)
        """
        return failIfThrows {
            return try (Data?).fetchAll(tx.database, sql: sql).compacted()
        }
    }

    func nextJob(forGroupId groupId: Data, tx: DBReadTransaction) -> GroupMessageProcessorJob? {
        return failIfThrows {
            let sql = """
            SELECT *
            FROM \(GroupMessageProcessorJob.databaseTableName)
            WHERE \(GroupMessageProcessorJob.CodingKeys.groupId.rawValue) = ?
            ORDER BY \(GroupMessageProcessorJob.CodingKeys.id.rawValue)
            """
            return try GroupMessageProcessorJob.fetchOne(tx.database, sql: sql, arguments: [groupId])
        }
    }

    func newestJobId(tx: DBReadTransaction) -> Int64? {
        return failIfThrows {
            let sql = """
            SELECT \(GroupMessageProcessorJob.CodingKeys.id.rawValue)
            FROM \(GroupMessageProcessorJob.databaseTableName)
            ORDER BY \(GroupMessageProcessorJob.CodingKeys.id.rawValue) DESC
            """
            return try Int64.fetchOne(tx.database, sql: sql)
        }
    }

    func existsJob(forGroupId groupId: Data, tx: DBReadTransaction) -> Bool {
        let sql = """
        SELECT 1 FROM \(GroupMessageProcessorJob.databaseTableName)
        WHERE \(GroupMessageProcessorJob.CodingKeys.groupId.rawValue) = ?
        """
        return failIfThrows {
            return try Bool.fetchOne(tx.database, sql: sql, arguments: [groupId]) ?? false
        }
    }

    func removeJob(withRowId rowId: Int64, tx: DBWriteTransaction) {
        failIfThrows {
            _ = try GroupMessageProcessorJob.deleteOne(tx.database, key: rowId)
        }
    }
}
