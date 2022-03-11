//
//  Copyright (c) 2022 Open Whisper Systems. All rights reserved.
//

import Foundation
import GRDB

public enum StoryFinder {
    public static func unviewedSenderCount(transaction: GRDBReadTransaction) -> Int {
        let sql = """
            SELECT COUNT(*) OVER ()
            FROM \(StoryMessageRecord.databaseTableName)
            WHERE direction = \(StoryMessageRecord.Direction.incoming.rawValue)
            AND json_extract(manifest, '$.incoming.viewed') = 0
            GROUP BY (
                CASE
                    WHEN groupId is NULL THEN authorUuid
                    ELSE groupId
                END
            )
            LIMIT 1
        """
        do {
            return try Int.fetchOne(transaction.database, sql: sql) ?? 0
        } catch {
            owsFailDebug("Failed to query unviewed story sender count \(error)")
            return 0
        }
    }

    public static func incomingStories(transaction: GRDBReadTransaction) -> [StoryMessageRecord] {
        let sql = """
            SELECT *
            FROM \(StoryMessageRecord.databaseTableName)
            WHERE direction = \(StoryMessageRecord.Direction.incoming.rawValue)
            ORDER BY timestamp DESC
        """

        do {
            return try StoryMessageRecord.fetchAll(transaction.database, sql: sql)
        } catch {
            owsFailDebug("Failed to fetch incoming stories \(error)")
            return []
        }
    }

    public static func incomingStoriesWithRowIds(_ rowIds: [Int64], transaction: GRDBReadTransaction) -> [StoryMessageRecord] {
        let sql = """
            SELECT *
            FROM \(StoryMessageRecord.databaseTableName)
            WHERE direction = \(StoryMessageRecord.Direction.incoming.rawValue)
            AND id IN (\(rowIds.map { "\($0)" }.joined(separator: ",")))
            ORDER BY timestamp DESC
        """

        do {
            return try StoryMessageRecord.fetchAll(transaction.database, sql: sql)
        } catch {
            owsFailDebug("Failed to fetch incoming stories \(error)")
            return []
        }
    }

    public static func latestStoryForThread(_ thread: TSThread, transaction: GRDBReadTransaction) -> StoryMessageRecord? {
        let threadQuery: String
        if let groupThread = thread as? TSGroupThread {
            threadQuery = "groupId = x'\(groupThread.groupId.hexadecimalString)'"
        } else if let contactThread = thread as? TSContactThread {
            guard let uuid = contactThread.contactAddress.uuid else {
                // No stories for contacts without UUIDs
                return nil
            }
            threadQuery = "authorUuid = '\(uuid.uuidString)' AND groupId is NULL"
        } else {
            owsFailDebug("Unexpected thread")
            return nil
        }

        let sql = """
            SELECT *
            FROM \(StoryMessageRecord.databaseTableName)
            WHERE \(threadQuery)
            ORDER BY timestamp DESC
            LIMIT 1
        """

        do {
            return try StoryMessageRecord.fetchOne(transaction.database, sql: sql)
        } catch {
            owsFailDebug("Failed to fetch incoming stories \(error)")
            return nil
        }
    }

    // The stories should be enumerated in order from "next to expire" to "last to expire".
    public static func enumerateExpiredStories(transaction: GRDBReadTransaction, block: @escaping (StoryMessageRecord, UnsafeMutablePointer<ObjCBool>) -> Void) {

        let sql = """
            SELECT *
            FROM \(StoryMessageRecord.databaseTableName)
            WHERE timestamp <= \(Date().ows_millisecondsSince1970 - StoryManager.storyLifetime)
            ORDER BY timestamp ASC
        """

        do {
            let cursor = try StoryMessageRecord.fetchCursor(transaction.database, sql: sql)
            while let record = try cursor.next() {
                var stop: ObjCBool = false
                block(record, &stop)
                if stop.boolValue {
                    return
                }
            }
        } catch {
            owsFail("error: \(error)")
        }
    }

    public static func oldestTimestamp(transaction: GRDBReadTransaction) -> UInt64? {
        let sql = """
            SELECT timestamp
            FROM \(StoryMessageRecord.databaseTableName)
            ORDER BY timestamp ASC
            LIMIT 1
        """

        do {
            return try UInt64.fetchOne(transaction.database, sql: sql)
        } catch {
            owsFailDebug("failed to lookup next story expiration \(error)")
            return nil
        }
    }
}
