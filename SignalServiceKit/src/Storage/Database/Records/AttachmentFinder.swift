//
// Copyright 2019 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
import GRDB
import SignalCoreKit

protocol AttachmentFinderAdapter {
    associatedtype ReadTransaction

    static func attachmentPointerIdsToMarkAsFailed(tx: ReadTransaction) -> [String]

    static func enumerateAttachmentPointersWithLazyRestoreFragments(transaction: ReadTransaction, block: @escaping (TSAttachmentPointer, UnsafeMutablePointer<ObjCBool>) -> Void)
}

// MARK: -

@objc
public class AttachmentFinder: NSObject, AttachmentFinderAdapter {

    let grdbAdapter: GRDBAttachmentFinderAdapter

    @objc
    public init(threadUniqueId: String) {
        self.grdbAdapter = GRDBAttachmentFinderAdapter(threadUniqueId: threadUniqueId)
    }

    // MARK: - static methods

    public static func attachmentPointerIdsToMarkAsFailed(tx: SDSAnyReadTransaction) -> [String] {
        switch tx.readTransaction {
        case .grdbRead(let grdbRead):
            return GRDBAttachmentFinderAdapter.attachmentPointerIdsToMarkAsFailed(tx: grdbRead)
        }
    }

    @objc
    public class func enumerateAttachmentPointersWithLazyRestoreFragments(transaction: SDSAnyReadTransaction, block: @escaping (TSAttachmentPointer, UnsafeMutablePointer<ObjCBool>) -> Void) {
        switch transaction.readTransaction {
        case .grdbRead(let grdbRead):
            return GRDBAttachmentFinderAdapter.enumerateAttachmentPointersWithLazyRestoreFragments(transaction: grdbRead, block: block)
        }
    }

    @objc
    public class func attachments(
        withAttachmentIds attachmentIds: [String],
        transaction: GRDBReadTransaction
    ) -> [TSAttachment] {
        guard !attachmentIds.isEmpty else {
            return []
        }
        return GRDBAttachmentFinderAdapter.attachments(
            withAttachmentIds: attachmentIds,
            transaction: transaction
        )
    }

    @objc
    public class func attachments(
        withAttachmentIds attachmentIds: [String],
        matchingContentType: String,
        transaction: GRDBReadTransaction
    ) -> [TSAttachment] {
        guard !attachmentIds.isEmpty else {
            return []
        }
        return GRDBAttachmentFinderAdapter.attachments(
            withAttachmentIds: attachmentIds,
            matchingContentType: matchingContentType,
            transaction: transaction
        )
    }

    @objc
    public class func attachments(
        withAttachmentIds attachmentIds: [String],
        ignoringContentType: String,
        transaction: GRDBReadTransaction
    ) -> [TSAttachment] {
        guard !attachmentIds.isEmpty else {
            return []
        }
        return GRDBAttachmentFinderAdapter.attachments(
            withAttachmentIds: attachmentIds,
            ignoringContentType: ignoringContentType,
            transaction: transaction
        )
    }

    @objc
    public class func existsAttachments(
        withAttachmentIds attachmentIds: [String],
        ignoringContentType: String,
        transaction: GRDBReadTransaction
    ) -> Bool {
        guard !attachmentIds.isEmpty else {
            return false
        }
        return GRDBAttachmentFinderAdapter.existsAttachments(
            withAttachmentIds: attachmentIds,
            ignoringContentType: ignoringContentType,
            transaction: transaction
        )
    }
}

// MARK: -

struct GRDBAttachmentFinderAdapter: AttachmentFinderAdapter {

    typealias ReadTransaction = GRDBReadTransaction

    let threadUniqueId: String

    init(threadUniqueId: String) {
        self.threadUniqueId = threadUniqueId
    }

    // MARK: - static methods

    static func attachmentPointerIdsToMarkAsFailed(tx: ReadTransaction) -> [String] {
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
            return try String.fetchAll(tx.database, sql: sql)
        } catch {
            owsFailDebug("error: \(error)")
            return []
        }
    }

    static func enumerateAttachmentPointersWithLazyRestoreFragments(transaction: GRDBReadTransaction, block: @escaping (TSAttachmentPointer, UnsafeMutablePointer<ObjCBool>) -> Void) {
        let sql: String = """
        SELECT *
        FROM \(AttachmentRecord.databaseTableName)
        WHERE \(attachmentColumn: .recordType) = \(SDSRecordType.attachmentPointer.rawValue)
        AND \(attachmentColumn: .lazyRestoreFragmentId) IS NOT NULL
        """
        let cursor = TSAttachment.grdbFetchCursor(sql: sql, transaction: transaction)
        do {
            while let attachment = try cursor.next() {
                guard let attachmentPointer = attachment as? TSAttachmentPointer else {
                    owsFailDebug("Unexpected object: \(type(of: attachment))")
                    return
                }
                var stop: ObjCBool = false
                block(attachmentPointer, &stop)
                if stop.boolValue {
                    return
                }
            }
        } catch {
            owsFailDebug("error: \(error)")
        }
    }

    static func attachments(
        withAttachmentIds attachmentIds: [String],
        ignoringContentType: String? = nil,
        matchingContentType: String? = nil,
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

    static func existsAttachments(
        withAttachmentIds attachmentIds: [String],
        ignoringContentType: String,
        transaction: GRDBReadTransaction
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
            exists = try Bool.fetchOne(transaction.database, sql: sql, arguments: [ignoringContentType]) ?? false
        } catch {
            owsFailDebug("Received unexpected error \(error)")
            exists = false
        }

        return exists
    }
}
