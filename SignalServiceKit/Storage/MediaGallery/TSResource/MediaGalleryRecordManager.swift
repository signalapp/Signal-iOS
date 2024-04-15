//
// Copyright 2024 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
import GRDB

public final class MediaGalleryRecordManager: NSObject {
    public static func setupDatabaseFunction(database: GRDB.Database) {
        database.add(function: isVisualMediaContentTypeDatabaseFunction)
    }

    internal static let isVisualMediaContentTypeDatabaseFunction = DatabaseFunction("IsVisualMediaContentType") { (args: [DatabaseValue]) -> DatabaseValueConvertible? in
        guard let contentType = String.fromDatabaseValue(args[0]) else {
            throw OWSAssertionError("unexpected arguments: \(args)")
        }

        return MimeTypeUtil.isSupportedVisualMediaMimeType(contentType)
    }

    private class func removeAnyGalleryRecord(attachmentStream: TSAttachmentStream, transaction: GRDBWriteTransaction) throws -> MediaGalleryRecord? {
        let sql = """
            DELETE FROM \(MediaGalleryRecord.databaseTableName) WHERE attachmentId = ? RETURNING *
        """
        guard let attachmentId = attachmentStream.grdbId else {
            owsFailDebug("attachmentId was unexpectedly nil")
            return nil
        }

        guard attachmentStream.albumMessageId != nil else {
            return nil
        }

        return try MediaGalleryRecord.fetchOne(transaction.database, sql: sql, arguments: [attachmentId.int64Value])
    }

    public class func insertForMigration(
        attachmentStream: TSAttachmentStream,
        transaction: GRDBWriteTransaction
    ) throws {
        _ = try insertGalleryRecordPrivate(attachmentStream: attachmentStream, transaction: transaction)
    }

    private class func insertGalleryRecordPrivate(
        attachmentStream: TSAttachmentStream,
        transaction: GRDBWriteTransaction
    ) throws -> MediaGalleryRecord? {
        guard let attachmentRowId = attachmentStream.grdbId else {
            throw OWSAssertionError("attachmentRowId was unexpectedly nil")
        }

        guard let messageUniqueId = attachmentStream.albumMessageId else {
            return nil
        }

        guard let message = TSMessage.anyFetchMessage(uniqueId: messageUniqueId, transaction: transaction.asAnyRead) else {
            owsFailDebug("message was unexpectedly nil")
            return nil
        }

        guard let messageRowId = message.grdbId else {
            owsFailDebug("message rowId was unexpectedly nil")
            return nil
        }

        guard let thread = message.thread(tx: transaction.asAnyRead) else {
            owsFailDebug("thread was unexpectedly nil")
            return nil
        }
        guard let threadId = thread.grdbId else {
            owsFailDebug("thread rowId was unexpectedly nil")
            return nil
        }

        guard
            let originalAlbumIndex = DependenciesBridge.shared.tsResourceStore.indexForBodyAttachmentId(
                .legacy(uniqueId: attachmentStream.uniqueId),
                on: message,
                tx: transaction.asAnyRead.asV2Read
            )
        else {
            owsFailDebug("originalAlbumIndex was unexpectedly nil")
            return nil
        }

        let galleryRecord = MediaGalleryRecord(attachmentId: attachmentRowId.int64Value,
                                               albumMessageId: messageRowId.int64Value,
                                               threadId: threadId.int64Value,
                                               originalAlbumOrder: originalAlbumIndex)

        try galleryRecord.insert(transaction.database)

        return galleryRecord
    }

    typealias ChangedAttachmentInfo = MediaGalleryResourceManager.ChangedTSResourceInfo

    private static let recentlyChangedMessageTimestampsByRowId = AtomicDictionary<Int64, UInt64>(lock: .sharedGlobal)
    private static let recentlyInsertedAttachments = AtomicArray<ChangedAttachmentInfo>(lock: .sharedGlobal)
    private static let recentlyRemovedAttachments = AtomicArray<ChangedAttachmentInfo>(lock: .sharedGlobal)

    public class func didInsert(attachmentStream: TSAttachmentStream, transaction: SDSAnyWriteTransaction) {
        let insertedRecord: MediaGalleryRecord?

        switch transaction.writeTransaction {
        case .grdbWrite(let grdbWrite):
            do {
                insertedRecord = try insertGalleryRecordPrivate(attachmentStream: attachmentStream,
                                                                transaction: grdbWrite)
            } catch {
                owsFailDebug("error: \(error)")
                insertedRecord = nil
            }
        }

        guard let insertedRecord = insertedRecord else {
            return
        }

        do {
            let attachment = try changedAttachmentInfo(for: insertedRecord,
                                                       attachmentUniqueId: attachmentStream.uniqueId,
                                                       transaction: transaction.unwrapGrdbRead)
            recentlyInsertedAttachments.append(attachment)
        } catch {
            owsFailDebug("error: \(error)")
            return
        }

        transaction.addSyncCompletion {
            // Clear the "recentlyRemoved" fields synchronously, so we don't mess with a later transaction.
            Self.recentlyChangedMessageTimestampsByRowId.removeAllValues()
            let recentlyInsertedAttachments = Self.recentlyInsertedAttachments.removeAll()
            if !recentlyInsertedAttachments.isEmpty {
                NotificationCenter.default.postNotificationNameAsync(
                    MediaGalleryResourceManager.newAttachmentsAvailableNotification,
                    object: recentlyInsertedAttachments
                )
            }
        }
    }

    private static func changedAttachmentInfo(for record: MediaGalleryRecord,
                                              attachmentUniqueId: String,
                                              transaction: GRDBReadTransaction) throws -> ChangedAttachmentInfo {
        let timestamp: UInt64
        if let maybeTimestamp = recentlyChangedMessageTimestampsByRowId[record.albumMessageId] {
            timestamp = maybeTimestamp
        } else {
            let timestampQuery = """
                SELECT \(interactionColumn: .receivedAtTimestamp)
                FROM \(InteractionRecord.databaseTableName)
                WHERE id = ?
            """
            guard let maybeTimestamp = try UInt64.fetchOne(transaction.database,
                                                           sql: timestampQuery,
                                                           arguments: [record.albumMessageId]) else {
                throw OWSGenericError("interaction already removed")
            }
            timestamp = maybeTimestamp
            recentlyChangedMessageTimestampsByRowId[record.albumMessageId] = timestamp
        }

        return ChangedAttachmentInfo(uniqueId: attachmentUniqueId,
                                     threadGrdbId: record.threadId,
                                     timestamp: timestamp)

    }

    public class func didRemove(attachmentStream: TSAttachmentStream, transaction: SDSAnyWriteTransaction) {
        let removedRecord: MediaGalleryRecord?
        switch transaction.writeTransaction {
        case .grdbWrite(let grdbWrite):
            do {
                removedRecord = try removeAnyGalleryRecord(attachmentStream: attachmentStream, transaction: grdbWrite)
            } catch {
                owsFailDebug("error: \(error)")
                removedRecord = nil
            }
        }

        guard let removedRecord = removedRecord else {
            return
        }

        do {
            let attachment = try changedAttachmentInfo(for: removedRecord,
                                                       attachmentUniqueId: attachmentStream.uniqueId,
                                                       transaction: transaction.unwrapGrdbRead)
            recentlyRemovedAttachments.append(attachment)
        } catch {
            owsFailDebug("error: \(error)")
            return
        }

        transaction.addSyncCompletion {
            // Clear the "recentlyRemoved" fields synchronously, so we don't mess with a later transaction.
            Self.recentlyChangedMessageTimestampsByRowId.removeAllValues()
            let recentlyRemovedAttachments = Self.recentlyRemovedAttachments.removeAll()
            if !recentlyRemovedAttachments.isEmpty {
                NotificationCenter.default.postNotificationNameAsync(
                    MediaGalleryResourceManager.didRemoveAttachmentsNotification,
                    object: recentlyRemovedAttachments
                )
            }
        }
    }

    public class func didRemove(message: TSMessage, transaction: SDSAnyWriteTransaction) {
        guard let messageRowId = message.sqliteRowId else {
            return
        }
        Self.recentlyChangedMessageTimestampsByRowId[messageRowId] = message.receivedAtTimestamp
    }

    public class func didRemoveAllContent(transaction: SDSAnyWriteTransaction) {
        switch transaction.writeTransaction {
        case .grdbWrite(let grdbWrite):
            do {
                try MediaGalleryRecord.deleteAll(grdbWrite.database)
            } catch {
                owsFailDebug("error: \(error)")
            }
        }
    }
}
