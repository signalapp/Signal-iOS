//
// Copyright 2023 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
import GRDB

public class TSAttachmentStore {

    public init() {}

    public func anyInsert(_ attachment: TSAttachment, tx: SDSAnyWriteTransaction) {
        attachment.anyInsert(transaction: tx)
    }

    public func attachments(
        withAttachmentIds attachmentIds: [String],
        tx: SDSAnyReadTransaction
    ) -> [TSAttachment] {
        return attachments(
            withAttachmentIds: attachmentIds,
            ignoringContentType: nil,
            matchingContentType: nil,
            transaction: tx.unwrapGrdbRead
        )
    }

    public func fetchAttachmentStream(
        uniqueId: String,
        tx: SDSAnyReadTransaction
    ) -> TSAttachmentStream? {
        TSAttachmentStream.anyFetchAttachmentStream(
            uniqueId: uniqueId,
            transaction: tx
        )
    }

    public func attachmentPointerIdsToMarkAsFailed(tx: SDSAnyReadTransaction) -> [String] {
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
            return try String.fetchAll(tx.unwrapGrdbRead.database, sql: sql)
        } catch {
            owsFailDebug("error: \(error)")
            return []
        }
    }

    public func attachments(
        withAttachmentIds attachmentIds: [String],
        matchingContentType: String,
        tx: SDSAnyReadTransaction
    ) -> [TSAttachment] {
        return attachments(
            withAttachmentIds: attachmentIds,
            ignoringContentType: nil,
            matchingContentType: matchingContentType,
            transaction: tx.unwrapGrdbRead
        )
    }

    public func attachments(
        withAttachmentIds attachmentIds: [String],
        ignoringContentType: String,
        tx: SDSAnyReadTransaction
    ) -> [TSAttachment] {
        return attachments(
            withAttachmentIds: attachmentIds,
            ignoringContentType: ignoringContentType,
            matchingContentType: nil,
            transaction: tx.unwrapGrdbRead
        )
    }

    public func existsAttachments(
        withAttachmentIds attachmentIds: [String],
        ignoringContentType: String,
        tx: SDSAnyReadTransaction
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
                tx.unwrapGrdbRead.database,
                sql: sql,
                arguments: [ignoringContentType]
            ) ?? false
        } catch {
            owsFailDebug("Received unexpected error \(error)")
            exists = false
        }

        return exists
    }

    public func allAttachmentIds(for message: TSMessage) -> Set<String> {
        var uniqueIds = Set<String>()

        uniqueIds.formUnion(message.attachmentIds ?? [])

        if let attachmentId = message.linkPreview?.legacyImageAttachmentId?.nilIfEmpty {
            uniqueIds.insert(attachmentId)
        }

        if let attachmentId = message.messageSticker?.legacyAttachmentId {
            uniqueIds.insert(attachmentId)
        }

        if let attachmentId = message.quotedMessage?.attachmentInfo()?.attachmentId {
            uniqueIds.insert(attachmentId)
        }

        if let attachmentId = message.contactShare?.legacyAvatarAttachmentId {
            uniqueIds.insert(attachmentId)
        }

        return uniqueIds
    }

    public func allAttachments(for message: TSMessage, tx: SDSAnyReadTransaction) -> [TSAttachmentReference] {
        let uniqueIds = self.allAttachmentIds(for: message)

        if uniqueIds.isEmpty { return [] }

        let idArray = Array(uniqueIds)

        let attachments = Dictionary(
            grouping: self.attachments(withAttachmentIds: idArray, tx: tx),
            by: \.uniqueId
        )
        return idArray.map {
            TSAttachmentReference(uniqueId: $0, attachment: attachments[$0]?.first)
        }
    }

    public func attachmentToUseInQuote(
        originalMessage: TSMessage,
        tx: SDSAnyReadTransaction
    ) -> TSAttachment? {
        for attachmentId in originalMessage.attachmentIds ?? [] {
            guard let attachment = TSAttachment.anyFetch(uniqueId: attachmentId, transaction: tx) else {
                continue
            }
            if attachment.isOversizeTextMimeType.negated {
                return attachment
            }
        }

        if
            let linkPreview = originalMessage.linkPreview,
            let attachmentId = linkPreview.legacyImageAttachmentId?.nilIfEmpty,
            let attachment = TSAttachment.anyFetch(uniqueId: attachmentId, transaction: tx)
        {
            return attachment
        }

        if
            let messageSticker = originalMessage.messageSticker,
            let legacyAttachmentId = messageSticker.legacyAttachmentId?.nilIfEmpty,
            let attachment = TSAttachment.anyFetch(uniqueId: legacyAttachmentId, transaction: tx)
        {
            return attachment
        }

        return nil
    }

    public func storyAttachmentReference(
        _ storyFileAttachment: StoryMessageFileAttachment,
        tx: SDSAnyReadTransaction
    ) -> StoryMessageTSAttachmentReference? {
        let attachment = self.attachments(withAttachmentIds: [storyFileAttachment.attachmentId], tx: tx).first
        return StoryMessageTSAttachmentReference(
            uniqueId: storyFileAttachment.attachmentId,
            attachment: attachment,
            caption: (attachment?.caption).map { caption in
                return StyleOnlyMessageBody(text: caption, collapsedStyles: storyFileAttachment.captionStyles)
            }
        )
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
