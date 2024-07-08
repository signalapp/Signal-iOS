//
// Copyright 2019 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
import GRDB

// MARK: - MediaGalleryRecordFinder (GRDB only)

public struct MediaGalleryRecordFinder {

    public let thread: TSThread

    /// Media will be restricted to this type. Otherwise there is no filtering.
    public var filter: AllMediaFilter

    public init(thread: TSThread, filter: AllMediaFilter) {
        owsAssertDebug(thread.grdbId != 0, "only supports GRDB")
        self.thread = thread
        self.filter = filter
    }

    // MARK: - 

    public var threadId: Int64 {
        guard let rowId = thread.grdbId else {
            owsFailDebug("thread.grdbId was unexpectedly nil")
            return 0
        }
        return rowId.int64Value
    }
}

extension MediaGalleryRecordFinder {

    public typealias EnumerationCompletion = MediaGalleryAttachmentFinder.EnumerationCompletion

    public typealias TSAttachmentUniqueId = String

    private enum Order: String, CustomStringConvertible {
        case ascending = "ASC"
        case descending = "DESC"

        var description: String { self.rawValue }
    }

    private struct QueryParts {
        let fromTableClauses: String
        let orderClauses: String
        let rangeClauses: String

        init(in dateInterval: DateInterval? = nil,
             excluding deletedAttachmentIds: Set<TSAttachmentUniqueId>,
             order: Order = .ascending,
             limit: Int? = nil,
             offset: Int? = nil,
             filter: AllMediaFilter?) {

            let contentTypeClause: String
            switch filter {
            case .gifs, .photos, .videos, .allPhotoVideoCategory:
                let isVisualMediaFuncName = MediaGalleryRecordManager.isVisualMediaContentTypeDatabaseFunction.name
                contentTypeClause = "AND \(isVisualMediaFuncName)(\(attachmentColumn: .contentType)) IS TRUE"
            case .voiceMessages, .audioFiles, .allAudioCategory:
                contentTypeClause = "AND (\(attachmentColumn: .contentType) like 'audio/%')"
            case .none:
                contentTypeClause = ""
            }
            let whereCondition: String = dateInterval.map {
                let startMillis = $0.start.ows_millisecondsSince1970
                // Both DateInterval and SQL BETWEEN are closed ranges, but rounding to millisecond precision loses range
                // at the boundaries, leading to the first millisecond of a month being considered part of the previous
                // month as well. Subtract 1ms from the end timestamp to avoid this.
                let endMillis = $0.end.ows_millisecondsSince1970 - 1
                var clauses = ["AND \(interactionColumn: .receivedAtTimestamp) BETWEEN \(startMillis) AND \(endMillis)"]
                switch filter {
                case .gifs:
                    // Note that this isn't quite the same as -[TSAttachmentStream
                    // hasAnimatedImageContent], which is used to label thumbnails as "GIF", because
                    // we don't try to test if the attachment is an animated sticker. Stickers are
                    // not supported. If we are unfortunate then image/webp and image/png are also
                    // *possibly* animated GIFs but you need to open the file to check.
                    // This code assumes that check is only needed for stickers.
                    clauses.append("AND (" + VideoAttachmentDetection.shared.attachmentStreamIsGIFOrLoopingVideoSQL + ") ")
                case .photos:
                    clauses.append("AND (" + VideoAttachmentDetection.shared.attachmentIsNonGIFImageSQL + ") ")
                case .videos:
                    clauses.append("AND (" + VideoAttachmentDetection.shared.attachmentIsNonLoopingVideoSQL + ") ")
                case .allPhotoVideoCategory:
                    break
                case .allAudioCategory:
                    break
                case .audioFiles, .voiceMessages:
                    break  // TODO(george): Filter content even more. Audio files are all downloaded audio except voice messages. Voice messages have attachmentType of .voicemessage. I have a truly marvelous demonstration of undownloaded audio which this margin is too narrow to contain.
                case .none:
                    // All media types.
                    break
                }
                return clauses.joined(separator: " ")
            } ?? ""

            let deletedAttachmentIdList = "(\"\(deletedAttachmentIds.joined(separator: "\",\""))\")"

            let limitModifier = "LIMIT \(limit ?? Int.max)"
            let offsetModifier = offset.map { "OFFSET \($0)" } ?? ""

            fromTableClauses = """
                FROM "media_gallery_items"
                INNER JOIN \(AttachmentRecord.databaseTableName)
                    ON media_gallery_items.attachmentId = \(attachmentColumnFullyQualified: .id)
                    \(contentTypeClause)
                INNER JOIN \(InteractionRecord.databaseTableName)
                    ON media_gallery_items.albumMessageId = \(interactionColumnFullyQualified: .id)
                    AND \(interactionColumn: .isViewOnceMessage) = FALSE
                WHERE media_gallery_items.threadId = ?
                    AND media_gallery_items.attachmentId NOT IN \(deletedAttachmentIdList)
                    \(whereCondition)
            """

            orderClauses = """
                ORDER BY
                    \(interactionColumn: .receivedAtTimestamp) \(order),
                    media_gallery_items.albumMessageId \(order),
                    media_gallery_items.originalAlbumOrder \(order)
            """

            rangeClauses = """
                \(limitModifier)
                \(offsetModifier)
            """
        }

        func select(_ result: String) -> String {
            return """
            SELECT \(result)
            \(fromTableClauses)
            \(orderClauses)
            \(rangeClauses)
            """
        }
    }

    /// An **unsanitized** interface for building queries against the `media_gallery_items` table
    /// and the associated AttachmentRecord and InteractionRecord tables.
    ///
    /// Contains one query parameter: the thread ID.
    private static func itemsQuery(result: String = "\(AttachmentRecord.databaseTableName).*",
                                   in dateInterval: DateInterval? = nil,
                                   excluding deletedAttachmentIds: Set<TSAttachmentUniqueId> = Set(),
                                   order: Order = .ascending,
                                   limit: Int? = nil,
                                   offset: Int? = nil,
                                   filter: AllMediaFilter?) -> String {
        let queryParts = QueryParts(in: dateInterval,
                                    excluding: deletedAttachmentIds,
                                    order: order,
                                    limit: limit,
                                    offset: offset,
                                    filter: filter)
        return queryParts.select(result)
    }

    public func rowIds(in givenInterval: DateInterval? = nil,
                       excluding deletedAttachmentIds: Set<TSAttachmentUniqueId>,
                       offset: Int,
                       ascending: Bool,
                       transaction: GRDBReadTransaction) -> [Int64] {
        let interval = givenInterval ?? DateInterval.init(start: Date(timeIntervalSince1970: 0),
                                                          end: .distantFutureForMillisecondTimestamp)
        let sql = Self.itemsQuery(result: "media_gallery_items.rowid",
                                  in: interval,
                                  excluding: deletedAttachmentIds,
                                  order: ascending ? .ascending : .descending,
                                  offset: offset,
                                  filter: filter)
        do {
            return try Int64.fetchAll(transaction.database, sql: sql, arguments: [threadId])
        } catch {
            DatabaseCorruptionState.flagDatabaseReadCorruptionIfNecessary(
                userDefaults: CurrentAppContext().appUserDefaults(),
                error: error
            )
            owsFail("Failed to fetch row ids")
        }
    }

    public func rowIdsAndDates(in givenInterval: DateInterval? = nil,
                               excluding deletedAttachmentIds: Set<TSAttachmentUniqueId>,
                               offset: Int,
                               ascending: Bool,
                               transaction: GRDBReadTransaction) -> [DatedMediaGalleryRecordId] {
        let interval = givenInterval ?? DateInterval.init(start: Date(timeIntervalSince1970: 0),
                                                          end: .distantFutureForMillisecondTimestamp)
        let sql = Self.itemsQuery(result: "media_gallery_items.rowid, \(interactionColumnFullyQualified: .receivedAtTimestamp)",
                                  in: interval,
                                  excluding: deletedAttachmentIds,
                                  order: ascending ? .ascending : .descending,
                                  offset: offset,
                                  filter: filter)
        do {
            return try DatedMediaGalleryRecordId.fetchAll(transaction.database, sql: sql, arguments: [threadId])
        } catch {
            DatabaseCorruptionState.flagDatabaseReadCorruptionIfNecessary(
                userDefaults: CurrentAppContext().appUserDefaults(),
                error: error
            )
            owsFail("Missing instance.")
        }
    }

    public func recentMediaAttachments(limit: Int, transaction: GRDBReadTransaction) -> [TSAttachment] {
        let sql = Self.itemsQuery(order: .descending, limit: limit, filter: filter)
        let cursor = TSAttachment.grdbFetchCursor(sql: sql, arguments: [threadId], transaction: transaction)
        var attachments = [TSAttachment]()
        while let next = try! cursor.next() {
            attachments.append(next)
        }
        return attachments
    }

    public func enumerateMediaAttachments(in dateInterval: DateInterval,
                                          excluding deletedAttachmentIds: Set<TSAttachmentUniqueId>,
                                          range: NSRange,
                                          transaction: GRDBReadTransaction,
                                          block: (Int, TSAttachment) -> Void) {
        let sql = Self.itemsQuery(in: dateInterval,
                                  excluding: deletedAttachmentIds,
                                  limit: range.length,
                                  offset: range.lowerBound,
                                  filter: filter)

        let cursor = TSAttachment.grdbFetchCursor(sql: sql, arguments: [threadId], transaction: transaction)
        var index = range.lowerBound
        while let next = try! cursor.next() {
            owsAssertDebug(range.contains(index))
            block(index, next)
            index += 1
        }
    }

    private func enumerateTimestamps(
        in interval: DateInterval,
        excluding deletedAttachmentIds: Set<TSAttachmentUniqueId>,
        order: Order,
        count: Int,
        transaction: GRDBReadTransaction,
        block: (DatedMediaGalleryRecordId) -> Void
    ) -> EnumerationCompletion {
        let sql = Self.itemsQuery(
            result: "media_gallery_items.rowid, \(interactionColumn: .receivedAtTimestamp)",
            in: interval,
            excluding: deletedAttachmentIds,
            order: order,
            limit: count,
            filter: filter
        )

        struct RowIDAndTimestamp: FetchableRecord {
            var rowid: Int64
            var timestamp: UInt64
            init(row: GRDB.Row) {
                rowid = row[0]
                timestamp = row[1]
            }
        }

        var actualCount = 0
        do {
            let cursor = try RowIDAndTimestamp.fetchCursor(transaction.database, sql: sql, arguments: [threadId])
            while let next = try cursor.next() {
                actualCount += 1
                block(.init(rowid: next.rowid, receivedAtTimestamp: next.timestamp))
            }
        } catch {
            DatabaseCorruptionState.flagDatabaseReadCorruptionIfNecessary(
                userDefaults: CurrentAppContext().appUserDefaults(),
                error: error
            )
            owsFail("Failed to enumerate timestamps")
        }
        if actualCount < count {
            return .reachedEnd
        }
        return .finished
    }

    public func enumerateTimestamps(
        before date: Date,
        excluding deletedAttachmentIds: Set<TSAttachmentUniqueId>,
        count: Int,
        transaction: GRDBReadTransaction,
        block: (DatedMediaGalleryRecordId) -> Void
    ) -> EnumerationCompletion {
        let interval = DateInterval(start: Date(timeIntervalSince1970: 0), end: date)
        return enumerateTimestamps(
            in: interval,
            excluding: deletedAttachmentIds,
            order: .descending,
            count: count,
            transaction: transaction,
            block: block
        )
    }

    public func enumerateTimestamps(
        after date: Date,
        excluding deletedAttachmentIds: Set<TSAttachmentUniqueId>,
        count: Int,
        transaction: GRDBReadTransaction,
        block: (DatedMediaGalleryRecordId) -> Void
    ) -> EnumerationCompletion {
        let interval = DateInterval(start: date, end: .distantFutureForMillisecondTimestamp)
        return enumerateTimestamps(
            in: interval,
            excluding: deletedAttachmentIds,
            order: .ascending,
            count: count,
            transaction: transaction,
            block: block
        )
    }

    // Disregards filter.
    public func rowid(of attachment: TSAttachmentStream,
                      in interval: DateInterval,
                      excluding deletedAttachmentIds: Set<TSAttachmentUniqueId>,
                      transaction: GRDBReadTransaction) -> Int64? {
        guard let attachmentRowId = attachment.grdbId else {
            owsFailDebug("attachment.grdbId was unexpectedly nil")
            return nil
        }

        let queryParts = QueryParts(in: interval,
                                    excluding: deletedAttachmentIds,
                                    filter: nil)
        let sql = """
            SELECT
                media_gallery_items.rowid
            \(queryParts.fromTableClauses)
                AND media_gallery_items.attachmentId = ?
        """

        do {
            return try Int64.fetchOne(transaction.database, sql: sql, arguments: [threadId, attachmentRowId])
        } catch {
            DatabaseCorruptionState.flagDatabaseReadCorruptionIfNecessary(
                userDefaults: CurrentAppContext().appUserDefaults(),
                error: error
            )
            owsFail("Failed to get row ID")
        }
    }

    /// Returns the number of attachments attached to `interaction`, whether or not they are media attachments. Disregards allowedMediaType.
    public func countAllAttachments(of interaction: TSInteraction, transaction: GRDBReadTransaction) throws -> UInt {
        let sql = """
            SELECT COUNT(*)
            FROM \(AttachmentRecord.databaseTableName)
            WHERE \(attachmentColumn: .albumMessageId) = ?
        """
        return try UInt.fetchOne(transaction.database, sql: sql, arguments: [interaction.uniqueId]) ?? 0
    }
}
