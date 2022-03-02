//
//  Copyright (c) 2022 Open Whisper Systems. All rights reserved.
//

import Foundation

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
}
