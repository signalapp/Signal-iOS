//
//  Copyright (c) 2021 Open Whisper Systems. All rights reserved.
//

import Foundation
import GRDB

protocol MediaGalleryFinder {
    associatedtype ReadTransaction

    func mostRecentMediaAttachment(transaction: ReadTransaction) -> TSAttachment?
    func mediaCount(transaction: ReadTransaction) -> UInt
    func mediaIndex(attachment: TSAttachmentStream, transaction: ReadTransaction) -> Int?
    func enumerateMediaAttachments(range: NSRange, transaction: ReadTransaction, block: @escaping (TSAttachment) -> Void)
}

@objc
public class AnyMediaGalleryFinder: NSObject {
    public typealias ReadTransaction = SDSAnyReadTransaction

    public lazy var yapAdapter = {
        return YAPDBMediaGalleryFinder(thread: self.thread)
    }()

    public lazy var grdbAdapter: GRDBMediaGalleryFinder = {
        return GRDBMediaGalleryFinder(thread: self.thread)
    }()

    let thread: TSThread
    public init(thread: TSThread) {
        self.thread = thread
    }
}

extension AnyMediaGalleryFinder: MediaGalleryFinder {
    public func mediaIndex(attachment: TSAttachmentStream, transaction: SDSAnyReadTransaction) -> Int? {
        switch transaction.readTransaction {
        case .grdbRead(let grdbRead):
            return grdbAdapter.mediaIndex(attachment: attachment, transaction: grdbRead)
        case .yapRead(let yapRead):
            guard let number = yapAdapter.mediaIndex(attachment: attachment, transaction: yapRead) else {
                return nil
            }
            return number.intValue
        }
    }

    public func enumerateMediaAttachments(range: NSRange, transaction: SDSAnyReadTransaction, block: @escaping (TSAttachment) -> Void) {
        switch transaction.readTransaction {
        case .grdbRead(let grdbRead):
            return grdbAdapter.enumerateMediaAttachments(range: range, transaction: grdbRead, block: block)
        case .yapRead(let yapRead):
            return yapAdapter.enumerateMediaAttachments(range: range, transaction: yapRead, block: block)
        }
    }

    public func mediaCount(transaction: SDSAnyReadTransaction) -> UInt {
        switch transaction.readTransaction {
        case .grdbRead(let grdbRead):
            return grdbAdapter.mediaCount(transaction: grdbRead)
        case .yapRead(let yapRead):
            return yapAdapter.mediaCount(transaction: yapRead)
        }
    }

    public func mostRecentMediaAttachment(transaction: SDSAnyReadTransaction) -> TSAttachment? {
        switch transaction.readTransaction {
        case .grdbRead(let grdbRead):
            return grdbAdapter.mostRecentMediaAttachment(transaction: grdbRead)
        case .yapRead(let yapRead):
            return yapAdapter.mostRecentMediaAttachment(transaction: yapRead)
        }
    }

    @objc(didInsertAttachmentStream:transaction:)
    public class func didInsert(attachmentStream: TSAttachmentStream, transaction: SDSAnyWriteTransaction) {
        switch transaction.writeTransaction {
        case .yapWrite:
            break
        case .grdbWrite(let grdbWrite):
            do {
                try GRDBMediaGalleryFinder.insertGalleryRecord(attachmentStream: attachmentStream, transaction: grdbWrite)
            } catch {
                owsFailDebug("error: \(error)")
            }
        }
    }

    @objc(didRemoveAttachmentStream:transaction:)
    public class func didRemove(attachmentStream: TSAttachmentStream, transaction: SDSAnyWriteTransaction) {
        switch transaction.writeTransaction {
        case .yapWrite:
            break
        case .grdbWrite(let grdbWrite):
            do {
                try GRDBMediaGalleryFinder.removeAnyGalleryRecord(attachmentStream: attachmentStream, transaction: grdbWrite)
            } catch {
                owsFailDebug("error: \(error)")
            }
        }
    }

    @objc
    public class func didRemoveAllContent(transaction: SDSAnyWriteTransaction) {
        switch transaction.writeTransaction {
        case .yapWrite:
            break
        case .grdbWrite(let grdbWrite):
            do {
                try GRDBMediaGalleryFinder.removeAllGalleryRecords(transaction: grdbWrite)
            } catch {
                owsFailDebug("error: \(error)")
            }
        }
    }
}

// MARK: - GRDB

@objc
public class GRDBMediaGalleryFinder: NSObject {

    let thread: TSThread
    init(thread: TSThread) {
        self.thread = thread
    }

    // MARK: - 

    var threadId: Int64 {
        guard let rowId = thread.grdbId else {
            owsFailDebug("thread.grdbId was unexpectedly nil")
            return 0
        }
        return rowId.int64Value
    }

    public static func setup(storage: GRDBDatabaseStorageAdapter) {
        storage.add(function: isVisualMediaContentTypeDatabaseFunction)
    }

    public static let isVisualMediaContentTypeDatabaseFunction = DatabaseFunction("IsVisualMediaContentType") { (args: [DatabaseValue]) -> DatabaseValueConvertible? in
        guard let contentType = String.fromDatabaseValue(args[0]) else {
            throw OWSAssertionError("unexpected arguments: \(args)")
        }

        return MIMETypeUtil.isVisualMedia(contentType)
    }

    public class func removeAnyGalleryRecord(attachmentStream: TSAttachmentStream, transaction: GRDBWriteTransaction) throws {
        let sql = """
            DELETE FROM \(MediaGalleryRecord.databaseTableName) WHERE attachmentId = ?
        """
        guard let attachmentId = attachmentStream.grdbId else {
            owsFailDebug("attachmentId was unexpectedly nil")
            return
        }

        guard attachmentStream.albumMessageId != nil else {
            Logger.verbose("not a gallery attachment")
            return
        }

        transaction.executeUpdate(sql: sql, arguments: [attachmentId.int64Value])
    }

    public class func insertGalleryRecord(attachmentStream: TSAttachmentStream, transaction: GRDBWriteTransaction) throws {
        guard let attachmentRowId = attachmentStream.grdbId else {
            owsFailDebug("attachmentRowId was unexpectedly nil")
            return
        }

        guard let messageUniqueId = attachmentStream.albumMessageId else {
            Logger.verbose("not a gallery attachment")
            return
        }

        guard let message = TSMessage.anyFetchMessage(uniqueId: messageUniqueId, transaction: transaction.asAnyRead) else {
            // This can happen *during* the YDB migration. We use `skipTouchObservations` as a proxy for
            // "are we running the ydb migration"
            assert(UIDatabaseObserver.skipTouchObservations, "message was unexpectedly nil")
            return
        }

        guard let messageRowId = message.grdbId else {
            owsFailDebug("message was unexpectedly nil")
            return
        }

        let thread = message.thread(transaction: transaction.asAnyRead)
        guard let threadId = thread.grdbId else {
            owsFailDebug("threadId was unexpectedly nil")
            return
        }

        guard let originalAlbumIndex = message.attachmentIds.firstIndex(of: attachmentStream.uniqueId) else {
            owsFailDebug("originalAlbumIndex was unexpectedly nil")
            return
        }

        let galleryRecord = MediaGalleryRecord(attachmentId: attachmentRowId.int64Value,
                                               albumMessageId: messageRowId.int64Value,
                                               threadId: threadId.int64Value,
                                               originalAlbumOrder: originalAlbumIndex)

        try galleryRecord.insert(transaction.database)
    }

    public class func removeAllGalleryRecords(transaction: GRDBWriteTransaction) throws {
        try MediaGalleryRecord.deleteAll(transaction.database)
    }
}

struct MediaGalleryRecord: Codable, FetchableRecord, PersistableRecord {
    static let databaseTableName = "media_gallery_items"

    let attachmentId: Int64
    let albumMessageId: Int64
    let threadId: Int64
    let originalAlbumOrder: Int
}

extension GRDBMediaGalleryFinder: MediaGalleryFinder {
    typealias ReadTransaction = GRDBReadTransaction

    public enum EnumerationCompletion {
        /// Enumeration completed normally.
        case finished
        /// The query ran out of items.
        case reachedEnd
    }

    private enum Order: String, CustomStringConvertible {
        case ascending = "ASC"
        case descending = "DESC"

        var description: String { self.rawValue }
    }

    /// An **unsanitized** interface for building queries against the `media_gallery_items` table
    /// and the associated AttachmentRecord and InteractionRecord tables.
    private static func itemsQuery(result: String = "\(AttachmentRecord.databaseTableName).*",
                                   for interaction: TSInteraction? = nil,
                                   in dateInterval: DateInterval? = nil,
                                   order: Order = .ascending,
                                   limit: Int? = nil,
                                   offset: Int? = nil) -> String {
        owsAssertDebug(interaction == nil || dateInterval == nil,
                       "cannot query based on both an interaction and a date interval")
        let whereCondition: String = interaction.map {
            return "AND media_gallery_items.albumMessageId = \($0.uniqueId)"
        } ?? dateInterval.map {
            let startMillis = $0.start.ows_millisecondsSince1970
            // Both DateInterval and SQL BETWEEN are closed ranges, but rounding to millisecond precision loses range
            // at the boundaries, leading to the first millisecond of a month being considered part of the previous
            // month as well. Subtract 1ms from the end timestamp to avoid this.
            let endMillis = $0.end.ows_millisecondsSince1970 - 1
            return "AND \(interactionColumn: .receivedAtTimestamp) BETWEEN \(startMillis) AND \(endMillis)"
        } ?? ""

        let limitModifier = limit.map { "LIMIT \($0)" } ?? ""
        let offsetModifier = offset.map { "OFFSET \($0)" } ?? ""

        return """
            SELECT \(result)
            FROM "media_gallery_items"
            INNER JOIN \(AttachmentRecord.databaseTableName)
                ON media_gallery_items.attachmentId = \(attachmentColumnFullyQualified: .id)
                AND IsVisualMediaContentType(\(attachmentColumn: .contentType)) IS TRUE
            INNER JOIN \(InteractionRecord.databaseTableName)
                ON media_gallery_items.albumMessageId = \(interactionColumnFullyQualified: .id)
                AND \(interactionColumn: .isViewOnceMessage) = FALSE
            WHERE media_gallery_items.threadId = ?
                \(whereCondition)
            ORDER BY
                \(interactionColumn: .receivedAtTimestamp) \(order),
                media_gallery_items.albumMessageId \(order),
                media_gallery_items.originalAlbumOrder \(order)
            \(limitModifier)
            \(offsetModifier)
        """
    }

    func mostRecentMediaAttachment(transaction: GRDBReadTransaction) -> TSAttachment? {
        let sql = Self.itemsQuery(order: .descending, limit: 1)
        let cursor = TSAttachment.grdbFetchCursor(sql: sql, arguments: [threadId], transaction: transaction)
        return try! cursor.next()
    }

    func mediaCount(transaction: GRDBReadTransaction) -> UInt {
        let sql = Self.itemsQuery(result: "COUNT(*)")
        return try! UInt.fetchOne(transaction.database, sql: sql, arguments: [threadId]) ?? 0
    }

    public func mediaCount(in dateInterval: DateInterval, transaction: GRDBReadTransaction) -> UInt {
        let sql = Self.itemsQuery(result: "COUNT(*)", in: dateInterval)
        return try! UInt.fetchOne(transaction.database, sql: sql, arguments: [threadId]) ?? 0
    }

    func enumerateMediaAttachments(range: NSRange, transaction: GRDBReadTransaction, block: (TSAttachment) -> Void) {
        let sql = Self.itemsQuery(limit: range.length, offset: range.lowerBound)

        let cursor = TSAttachment.grdbFetchCursor(sql: sql, arguments: [threadId], transaction: transaction)
        while let next = try! cursor.next() {
            block(next)
        }
    }

    public func enumerateMediaAttachments(in dateInterval: DateInterval,
                                          range: NSRange,
                                          transaction: GRDBReadTransaction,
                                          block: (Int, TSAttachment) -> Void) {
        let sql = Self.itemsQuery(in: dateInterval, limit: range.length, offset: range.lowerBound)

        let cursor = TSAttachment.grdbFetchCursor(sql: sql, arguments: [threadId], transaction: transaction)
        var index = range.lowerBound
        while let next = try! cursor.next() {
            owsAssertDebug(range.contains(index))
            block(index, next)
            index += 1
        }
    }

    public func enumerateMediaAttachments(for interaction: TSInteraction,
                                          transaction: GRDBReadTransaction,
                                          block: (TSAttachment) -> Void) {
        let sql = Self.itemsQuery(for: interaction)

        let cursor = TSAttachment.grdbFetchCursor(sql: sql, arguments: [threadId], transaction: transaction)
        while let next = try! cursor.next() {
            block(next)
        }
    }

    private func enumerateTimestamps(in interval: DateInterval,
                                     order: Order,
                                     count: Int,
                                     transaction: GRDBReadTransaction,
                                     block: (Date) -> Void) -> EnumerationCompletion {
        let sql = Self.itemsQuery(result: "\(interactionColumn: .receivedAtTimestamp)",
                                  in: interval,
                                  order: order,
                                  limit: count)

        let cursor = try! UInt64.fetchCursor(transaction.database, sql: sql, arguments: [threadId])
        var actualCount = 0
        while let next = try! cursor.next() {
            actualCount += 1
            block(Date(millisecondsSince1970: next))
        }
        if actualCount < count {
            return .reachedEnd
        }
        return .finished

    }

    public func enumerateTimestamps(before date: Date,
                                    count: Int,
                                    transaction: GRDBReadTransaction,
                                    block: (Date) -> Void) -> EnumerationCompletion {
        let interval = DateInterval(start: Date(timeIntervalSince1970: 0), end: date)
        return enumerateTimestamps(in: interval,
                                   order: .descending,
                                   count: count,
                                   transaction: transaction,
                                   block: block)
    }

    public func enumerateTimestamps(after date: Date,
                                    count: Int,
                                    transaction: GRDBReadTransaction,
                                    block: (Date) -> Void) -> EnumerationCompletion {
        let interval = DateInterval(start: date, end: .distantFutureForMillisecondTimestamp)
        return enumerateTimestamps(in: interval,
                                   order: .ascending,
                                   count: count,
                                   transaction: transaction,
                                   block: block)
    }

    func mediaIndex(attachment: TSAttachmentStream, transaction: GRDBReadTransaction) -> Int? {
        let sql = """
        SELECT mediaIndex
        FROM (
            SELECT
                ROW_NUMBER() OVER (
                    ORDER BY
                        \(interactionColumn: .receivedAtTimestamp),
                        media_gallery_items.albumMessageId,
                        media_gallery_items.originalAlbumOrder
                ) - 1 as mediaIndex,
                media_gallery_items.attachmentId
            FROM media_gallery_items
            INNER JOIN \(AttachmentRecord.databaseTableName)
                ON media_gallery_items.attachmentId = \(attachmentColumnFullyQualified: .id)
                AND IsVisualMediaContentType(\(attachmentColumn: .contentType)) IS TRUE
            INNER JOIN \(InteractionRecord.databaseTableName)
                ON media_gallery_items.albumMessageId = \(interactionColumnFullyQualified: .id)
                AND \(interactionColumn: .isViewOnceMessage) = FALSE
            WHERE media_gallery_items.threadId = ?
        )
        WHERE attachmentId = ?
        """

        guard let attachmentRowId = attachment.grdbId else {
            owsFailDebug("attachment.grdbId was unexpectedly nil")
            return nil
        }

        return try! Int.fetchOne(transaction.database, sql: sql, arguments: [threadId, attachmentRowId])
    }
}
