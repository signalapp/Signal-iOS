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
}
