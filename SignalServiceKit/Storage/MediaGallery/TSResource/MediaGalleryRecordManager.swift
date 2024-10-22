//
// Copyright 2024 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
public import GRDB

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

    private class func removeAnyGalleryRecord(
        attachmentStream: ReferencedTSResourceStream,
        transaction: GRDBWriteTransaction
    ) throws -> MediaGalleryRecord? {
        let legacyAttachmentRowId: Int64

        switch attachmentStream.reference.concreteType {
        case .legacy(let tsAttachmentRef):
            guard
                let tsAttachment = tsAttachmentRef.attachment,
                let attachmentRowId = tsAttachment.sqliteRowId
            else {
                throw OWSAssertionError("attachmentRowId was unexpectedly nil")
            }
            legacyAttachmentRowId = attachmentRowId
            guard tsAttachment.albumMessageId != nil else {
                return nil
            }
        case .v2(let attachmentReference):
            switch attachmentReference.owner {
            case .message(.bodyAttachment):
                break
            default:
                // we only index body attachments
                return nil
            }
            // TODO: handle MediaGalleryRecords with v2 attachments
            return nil
        }

        let sql = """
            DELETE FROM \(MediaGalleryRecord.databaseTableName) WHERE attachmentId = ? RETURNING *
        """

        return try MediaGalleryRecord.fetchOne(transaction.database, sql: sql, arguments: [legacyAttachmentRowId])
    }

    public class func insertForMigration(
        attachmentStream: TSAttachmentStream,
        transaction: GRDBWriteTransaction
    ) throws {
        try insertGalleryRecordPrivate(
            attachmentStream: ReferencedTSResourceStream(
                reference: TSAttachmentReference(uniqueId: attachmentStream.uniqueId, attachment: attachmentStream),
                attachmentStream: attachmentStream
            ),
            transaction: transaction
        )
    }

    @discardableResult
    private class func insertGalleryRecordPrivate(
        attachmentStream: ReferencedTSResourceStream,
        transaction: GRDBWriteTransaction
    ) throws -> MediaGalleryRecord? {
        guard let message = attachmentStream.reference.fetchOwningMessage(tx: transaction.asAnyRead) else {
            return nil
        }

        let legacyAttachmentRowId: Int64
        let originalAlbumOrder: Int

        switch attachmentStream.reference.concreteType {
        case .legacy(let tsAttachmentRef):
            guard
                let tsAttachment = tsAttachmentRef.attachment,
                let attachmentRowId = tsAttachment.sqliteRowId
            else {
                throw OWSAssertionError("attachmentRowId was unexpectedly nil")
            }
            legacyAttachmentRowId = attachmentRowId
            guard let index = message.attachmentIds?.firstIndex(of: tsAttachmentRef.uniqueId) else {
                owsFailDebug("originalAlbumIndex was unexpectedly nil")
                return nil
            }
            originalAlbumOrder = index
        case .v2(let attachmentReference):
            switch attachmentReference.owner {
            case .message(.bodyAttachment(let metadata)):
                originalAlbumOrder = Int(metadata.orderInOwner)
            default:
                // Only index body attachments
                return nil
            }
            // TODO: handle MediaGalleryRecords with v2 attachments
            return nil
        }

        guard let messageRowId = message.sqliteRowId else {
            owsFailDebug("message rowId was unexpectedly nil")
            return nil
        }

        guard let thread = message.thread(tx: transaction.asAnyRead) else {
            owsFailDebug("thread was unexpectedly nil")
            return nil
        }
        guard let threadId = thread.sqliteRowId else {
            owsFailDebug("thread rowId was unexpectedly nil")
            return nil
        }

        let galleryRecord = MediaGalleryRecord(
            attachmentId: legacyAttachmentRowId,
            albumMessageId: messageRowId,
            threadId: threadId,
            originalAlbumOrder: originalAlbumOrder
        )

        try galleryRecord.insert(transaction.database)

        return galleryRecord
    }

    typealias ChangedAttachmentInfo = MediaGalleryResource.ChangedResourceInfo

    private static let recentlyChangedMessageTimestampsByRowId = AtomicDictionary<Int64, UInt64>(lock: .sharedGlobal)
    private static let recentlyInsertedAttachments = AtomicArray<ChangedAttachmentInfo>(lock: .sharedGlobal)
    private static let recentlyRemovedAttachments = AtomicArray<ChangedAttachmentInfo>(lock: .sharedGlobal)

    public class func didInsert(attachmentStream: ReferencedTSResourceStream, transaction: SDSAnyWriteTransaction) {
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
            let attachment = try changedAttachmentInfo(
                for: insertedRecord,
                attachmentId: attachmentStream.reference.mediaGalleryResourceId,
                transaction: transaction.unwrapGrdbRead
            )
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
                    MediaGalleryResource.newAttachmentsAvailableNotification,
                    object: recentlyInsertedAttachments
                )
            }
        }
    }

    private static func changedAttachmentInfo(
        for record: MediaGalleryRecord,
        attachmentId: MediaGalleryResourceId,
        transaction: GRDBReadTransaction
    ) throws -> ChangedAttachmentInfo {
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

        return ChangedAttachmentInfo(
            attachmentId: attachmentId,
            threadGrdbId: record.threadId,
            timestamp: timestamp
        )

    }

    public class func didRemove(attachmentStream: ReferencedTSResourceStream, transaction: SDSAnyWriteTransaction) {
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
            let attachment = try changedAttachmentInfo(
                for: removedRecord,
                attachmentId: attachmentStream.reference.mediaGalleryResourceId,
                transaction: transaction.unwrapGrdbRead
            )
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
                    MediaGalleryResource.didRemoveAttachmentsNotification,
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
