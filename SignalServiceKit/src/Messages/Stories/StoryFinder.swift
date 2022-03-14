//
//  Copyright (c) 2022 Open Whisper Systems. All rights reserved.
//

import Foundation
import GRDB

@objc
public class StoryFinder: NSObject {
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
        latestStoryForContext(thread.storyContext, transaction: transaction)
    }

    public static func latestStoryForContext(_ context: StoryContext, transaction: GRDBReadTransaction) -> StoryMessageRecord? {

        guard let contextQuery = context.query else { return nil }

        let sql = """
            SELECT *
            FROM \(StoryMessageRecord.databaseTableName)
            WHERE \(contextQuery)
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

    public static func enumerateStoriesForContext(_ context: StoryContext, transaction: GRDBReadTransaction, block: @escaping (StoryMessageRecord, UnsafeMutablePointer<ObjCBool>) -> Void) {

        guard let contextQuery = context.query else { return }

        let sql = """
            SELECT *
            FROM \(StoryMessageRecord.databaseTableName)
            WHERE \(contextQuery)
            ORDER BY timestamp DESC
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
            owsFailDebug("error: \(error)")
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
            owsFailDebug("error: \(error)")
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

    @objc
    public static func story(timestamp: UInt64, author: SignalServiceAddress, transaction: GRDBReadTransaction) -> StoryMessageRecord? {
        guard let authorUuid = author.uuid else {
            owsFailDebug("Cannot query story for author without UUID")
            return nil
        }

        let sql = """
            SELECT *
            FROM \(StoryMessageRecord.databaseTableName)
            WHERE authorUuid = '\(authorUuid.uuidString)'
            AND timestamp = \(timestamp)
            ORDER BY timestamp DESC
            LIMIT 1
        """

        do {
            return try StoryMessageRecord.fetchOne(transaction.database, sql: sql)
        } catch {
            owsFailDebug("Failed to fetch story \(error)")
            return nil
        }
    }
}

private extension StoryContext {
    var query: String? {
        switch self {
        case .groupId(let data):
            return "groupId = x'\(data.hexadecimalString)'"
        case .authorUuid(let uuid):
            return "authorUuid = '\(uuid.uuidString)' AND groupId is NULL"
        case .none:
            return nil
        }
    }
}
