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
}
