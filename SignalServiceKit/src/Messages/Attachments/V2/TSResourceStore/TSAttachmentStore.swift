//
// Copyright 2023 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
import GRDB

public protocol TSAttachmentStore {

    func anyInsert(
        _ attachment: TSAttachment,
        tx: DBWriteTransaction
    )

    func attachments(
        withAttachmentIds attachmentIds: [String],
        tx: DBReadTransaction
    ) -> [TSAttachment]

    func fetchAttachmentStream(
        uniqueId: String,
        tx: DBReadTransaction
    ) -> TSAttachmentStream?

    func updateAsUploaded(
        attachmentStream: TSAttachmentStream,
        encryptionKey: Data,
        digest: Data,
        cdnKey: String,
        cdnNumber: UInt32,
        uploadTimestamp: UInt64,
        tx: DBWriteTransaction
    )

    func attachmentPointerIdsToMarkAsFailed(
        tx: DBReadTransaction
    ) -> [String]

    func attachments(
        withAttachmentIds attachmentIds: [String],
        matchingContentType: String,
        tx: DBReadTransaction
    ) -> [TSAttachment]

    func attachments(
        withAttachmentIds attachmentIds: [String],
        ignoringContentType: String,
        tx: DBReadTransaction
    ) -> [TSAttachment]

    func existsAttachments(
        withAttachmentIds attachmentIds: [String],
        ignoringContentType: String,
        tx: DBReadTransaction
    ) -> Bool

    // MARK: - TSMessage Writes

    func addBodyAttachments(
        _ attachments: [TSAttachment],
        to message: TSMessage,
        tx: DBWriteTransaction
    )

    func removeBodyAttachment(
        _ attachment: TSAttachment,
        from message: TSMessage,
        tx: DBWriteTransaction
    )
}

public class TSAttachmentStoreImpl: TSAttachmentStore {

    public init() {}

    public func anyInsert(_ attachment: TSAttachment, tx: DBWriteTransaction) {
        attachment.anyInsert(transaction: SDSDB.shimOnlyBridge(tx))
    }

    public func attachments(
        withAttachmentIds attachmentIds: [String],
        tx: DBReadTransaction
    ) -> [TSAttachment] {
        return attachments(
            withAttachmentIds: attachmentIds,
            ignoringContentType: nil,
            matchingContentType: nil,
            transaction: SDSDB.shimOnlyBridge(tx).unwrapGrdbRead
        )
    }

    public func fetchAttachmentStream(
        uniqueId: String,
        tx: DBReadTransaction
    ) -> TSAttachmentStream? {
        TSAttachmentStream.anyFetchAttachmentStream(
            uniqueId: uniqueId,
            transaction: SDSDB.shimOnlyBridge(tx)
        )
    }

    public func updateAsUploaded(
        attachmentStream: TSAttachmentStream,
        encryptionKey: Data,
        digest: Data,
        cdnKey: String,
        cdnNumber: UInt32,
        uploadTimestamp: UInt64,
        tx: DBWriteTransaction
    ) {
        attachmentStream.updateAsUploaded(
            withEncryptionKey: encryptionKey,
            digest: digest,
            serverId: 0, // Only used in cdn0 uploads, which aren't supported here.
            cdnKey: cdnKey,
            cdnNumber: cdnNumber,
            uploadTimestamp: uploadTimestamp,
            transaction: SDSDB.shimOnlyBridge(tx)
        )
    }

    public func attachmentPointerIdsToMarkAsFailed(tx: DBReadTransaction) -> [String] {
        // In DEBUG builds, confirm that we use the expected index.
        let indexedBy: String
        #if DEBUG
        indexedBy = "INDEXED BY index_attachments_toMarkAsFailed"
        #else
        indexedBy = ""
        #endif

        let sql: String = """
        SELECT \(attachmentColumn: .uniqueId)
        FROM \(AttachmentRecord.databaseTableName)
        \(indexedBy)
        WHERE \(attachmentColumn: .recordType) = \(SDSRecordType.attachmentPointer.rawValue)
        AND \(attachmentColumn: .state) IN (
            \(TSAttachmentPointerState.enqueued.rawValue),
            \(TSAttachmentPointerState.downloading.rawValue)
        )
        """
        do {
            return try String.fetchAll(SDSDB.shimOnlyBridge(tx).unwrapGrdbRead.database, sql: sql)
        } catch {
            owsFailDebug("error: \(error)")
            return []
        }
    }

    public func attachments(
        withAttachmentIds attachmentIds: [String],
        matchingContentType: String,
        tx: DBReadTransaction
    ) -> [TSAttachment] {
        return attachments(
            withAttachmentIds: attachmentIds,
            ignoringContentType: nil,
            matchingContentType: matchingContentType,
            transaction: SDSDB.shimOnlyBridge(tx).unwrapGrdbRead
        )
    }

    public func attachments(
        withAttachmentIds attachmentIds: [String],
        ignoringContentType: String,
        tx: DBReadTransaction
    ) -> [TSAttachment] {
        return attachments(
            withAttachmentIds: attachmentIds,
            ignoringContentType: ignoringContentType,
            matchingContentType: nil,
            transaction: SDSDB.shimOnlyBridge(tx).unwrapGrdbRead
        )
    }

    public func existsAttachments(
        withAttachmentIds attachmentIds: [String],
        ignoringContentType: String,
        tx: DBReadTransaction
    ) -> Bool {
        guard !attachmentIds.isEmpty else { return false }

        let sql = """
            SELECT EXISTS(
                SELECT 1
                FROM \(AttachmentRecord.databaseTableName)
                WHERE \(attachmentColumn: .uniqueId) IN (\(attachmentIds.map { "\'\($0)'" }.joined(separator: ",")))
                AND \(attachmentColumn: .contentType) != ?
                LIMIT 1
            )
        """

        let exists: Bool
        do {
            exists = try Bool.fetchOne(
                SDSDB.shimOnlyBridge(tx).unwrapGrdbRead.database,
                sql: sql,
                arguments: [ignoringContentType]
            ) ?? false
        } catch {
            owsFailDebug("Received unexpected error \(error)")
            exists = false
        }

        return exists
    }

    // MARK: - TSMessage Writes

    public func addBodyAttachments(
        _ attachments: [TSAttachment],
        to message: TSMessage,
        tx: DBWriteTransaction
    ) {
        message.anyUpdateMessage(transaction: SDSDB.shimOnlyBridge(tx)) { message in
            var attachmentIds = message.attachmentIds
            var attachmentIdSet = Set(attachmentIds)
            for attachment in attachments {
                if attachmentIdSet.contains(attachment.uniqueId) {
                    continue
                }
                attachmentIds.append(attachment.uniqueId)
                attachmentIdSet.insert(attachment.uniqueId)
            }
            message.setLegacyBodyAttachmentIds(attachmentIds)
        }
    }

    public func removeBodyAttachment(
        _ attachment: TSAttachment,
        from message: TSMessage,
        tx: DBWriteTransaction
    ) {
        owsAssertDebug(message.attachmentIds.contains(attachment.uniqueId))
        attachment.anyRemove(transaction: SDSDB.shimOnlyBridge(tx))

        message.anyUpdateMessage(transaction: SDSDB.shimOnlyBridge(tx)) { message in
            var attachmentIds = message.attachmentIds
            attachmentIds.removeAll(where: { $0 == attachment.uniqueId })
            message.setLegacyBodyAttachmentIds(attachmentIds)
        }
    }

    // MARK: - Helpers

    private func attachments(
        withAttachmentIds attachmentIds: [String],
        ignoringContentType: String?,
        matchingContentType: String?,
        transaction: GRDBReadTransaction
    ) -> [TSAttachment] {
        guard !attachmentIds.isEmpty else { return [] }

        var sql = """
            SELECT * FROM \(AttachmentRecord.databaseTableName)
            WHERE \(attachmentColumn: .uniqueId) IN (\(attachmentIds.map { "\'\($0)'" }.joined(separator: ",")))
        """

        let arguments: StatementArguments

        if let ignoringContentType = ignoringContentType {
            sql += " AND \(attachmentColumn: .contentType) != ?"
            arguments = [ignoringContentType]
        } else if let matchingContentType = matchingContentType {
            sql += " AND \(attachmentColumn: .contentType) = ?"
            arguments = [matchingContentType]
        } else {
            arguments = []
        }

        let cursor = TSAttachment.grdbFetchCursor(sql: sql, arguments: arguments, transaction: transaction)

        var attachments = [TSAttachment]()

        do {
            while let attachment = try cursor.next() {
                attachments.append(attachment)
            }
        } catch {
            owsFailDebug("unexpected error \(error)")
        }

        return attachments.sorted { lhs, rhs -> Bool in
            guard let lhsIndex = attachmentIds.firstIndex(of: lhs.uniqueId) else {
                owsFailDebug("unexpected attachment \(lhs.uniqueId)")
                return false
            }
            guard let rhsIndex = attachmentIds.firstIndex(of: rhs.uniqueId) else {
                owsFailDebug("unexpected attachment \(rhs.uniqueId)")
                return false
            }
            return lhsIndex < rhsIndex
        }
    }
}

#if TESTABLE_BUILD

open class TSAttachmentStoreMock: TSAttachmentStore {

    public init() {}

    public var attachments = [TSAttachment]()

    public func anyInsert(_ attachment: TSAttachment, tx: DBWriteTransaction) {
        self.attachments.append(attachment)
    }

    public func fetchAttachmentStream(uniqueId: String, tx: DBReadTransaction) -> TSAttachmentStream? {
        return nil
    }

    public func updateAsUploaded(
        attachmentStream: TSAttachmentStream,
        encryptionKey: Data,
        digest: Data,
        cdnKey: String,
        cdnNumber: UInt32,
        uploadTimestamp: UInt64,
        tx: DBWriteTransaction
    ) { }

    public func attachments(withAttachmentIds attachmentIds: [String], tx: DBReadTransaction) -> [TSAttachment] {
        return attachments.filter { attachmentIds.contains($0.uniqueId) }
    }

    public func attachmentPointerIdsToMarkAsFailed(tx: DBReadTransaction) -> [String] {
        return attachments.lazy
            .filter {
                switch ($0 as? TSAttachmentPointer)?.state {
                case .none, .failed, .pendingManualDownload, .pendingMessageRequest:
                    return false
                case .downloading, .enqueued:
                    return true
                }
            }
            .map(\.uniqueId)
    }

    public func attachments(
        withAttachmentIds attachmentIds: [String],
        matchingContentType: String,
        tx: DBReadTransaction
    ) -> [TSAttachment] {
        return attachments.filter {
            guard attachmentIds.contains($0.uniqueId) else {
                return false
            }
            return $0.contentType == matchingContentType
        }
    }

    public func attachments(
        withAttachmentIds attachmentIds: [String],
        ignoringContentType: String,
        tx: DBReadTransaction
    ) -> [TSAttachment] {
        return attachments.filter {
            guard attachmentIds.contains($0.uniqueId) else {
                return false
            }
            return $0.contentType != ignoringContentType
        }
    }

    public func existsAttachments(
        withAttachmentIds attachmentIds: [String],
        ignoringContentType: String,
        tx: DBReadTransaction
    ) -> Bool {
        return attachments.contains(where: {
            guard attachmentIds.contains($0.uniqueId) else {
                return false
            }
            return $0.contentType != ignoringContentType
        })
    }

    // MARK: - TSMessage Writes

    public func addBodyAttachments(
        _ attachments: [TSAttachment],
        to message: TSMessage,
        tx: DBWriteTransaction
    ) {}

    public func removeBodyAttachment(
        _ attachment: TSAttachment,
        from message: TSMessage,
        tx: DBWriteTransaction
    ) {}
}

#endif
