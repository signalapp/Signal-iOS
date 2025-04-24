//
// Copyright 2025 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
import GRDB

struct GroupMessageProcessorJobStore {
    func allEnqueuedGroupIds(tx: DBReadTransaction) throws -> [Data] {
        let sql = """
            SELECT DISTINCT \(GroupMessageProcessorJob.CodingKeys.groupId.rawValue)
            FROM \(GroupMessageProcessorJob.databaseTableName)
            """
        do {
            return try (Data?).fetchAll(tx.database, sql: sql).compacted()
        } catch {
            throw error.grdbErrorForLogging
        }
    }

    func nextJobs(
        forGroupId groupId: Data,
        batchSize: Int,
        tx: DBReadTransaction
    ) throws -> [GroupMessageProcessorJob] {
        do {
            let sql = """
                SELECT *
                FROM \(GroupMessageProcessorJob.databaseTableName)
                WHERE \(GroupMessageProcessorJob.CodingKeys.groupId.rawValue) = ?
                ORDER BY \(GroupMessageProcessorJob.CodingKeys.id.rawValue)
                LIMIT \(batchSize)
                """
            return try GroupMessageProcessorJob.fetchAll(tx.database, sql: sql, arguments: [groupId])
        } catch {
            throw error.grdbErrorForLogging
        }
    }

    public func existsJob(forGroupId groupId: Data, tx: DBReadTransaction) throws -> Bool {
        let sql = """
            SELECT 1 FROM \(GroupMessageProcessorJob.databaseTableName)
            WHERE \(GroupMessageProcessorJob.CodingKeys.groupId.rawValue) = ?
            """
        do {
            return try Bool.fetchOne(tx.database, sql: sql, arguments: [groupId]) ?? false
        } catch {
            throw error.grdbErrorForLogging
        }
    }

    public func removeJob(withRowId rowId: Int64, tx: DBWriteTransaction) throws {
        do {
            _ = try GroupMessageProcessorJob.deleteOne(tx.database, key: rowId)
        } catch {
            throw error.grdbErrorForLogging
        }
    }
}
