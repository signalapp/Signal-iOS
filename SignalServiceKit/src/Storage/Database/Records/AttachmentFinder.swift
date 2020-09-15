//
//  Copyright (c) 2020 Open Whisper Systems. All rights reserved.
//

import Foundation
import GRDB

protocol AttachmentFinderAdapter {
    associatedtype ReadTransaction

    static func unfailedAttachmentPointerIds(transaction: ReadTransaction) -> [String]

    static func enumerateAttachmentPointersWithLazyRestoreFragments(transaction: ReadTransaction, block: @escaping (TSAttachmentPointer, UnsafeMutablePointer<ObjCBool>) -> Void)
}

// MARK: -

@objc
public class AttachmentFinder: NSObject, AttachmentFinderAdapter {

    let yapAdapter: YAPDBAttachmentFinderAdapter
    let grdbAdapter: GRDBAttachmentFinderAdapter

    @objc
    public init(threadUniqueId: String) {
        self.yapAdapter = YAPDBAttachmentFinderAdapter(threadUniqueId: threadUniqueId)
        self.grdbAdapter = GRDBAttachmentFinderAdapter(threadUniqueId: threadUniqueId)
    }

    // MARK: - static methods

    @objc
    public class func unfailedAttachmentPointerIds(transaction: SDSAnyReadTransaction) -> [String] {
        switch transaction.readTransaction {
        case .yapRead(let yapRead):
            return YAPDBAttachmentFinderAdapter.unfailedAttachmentPointerIds(transaction: yapRead)
        case .grdbRead(let grdbRead):
            return GRDBAttachmentFinderAdapter.unfailedAttachmentPointerIds(transaction: grdbRead)
        }
    }

    @objc
    public class func enumerateAttachmentPointersWithLazyRestoreFragments(transaction: SDSAnyReadTransaction, block: @escaping (TSAttachmentPointer, UnsafeMutablePointer<ObjCBool>) -> Void) {
        switch transaction.readTransaction {
        case .yapRead(let yapRead):
            return YAPDBAttachmentFinderAdapter.enumerateAttachmentPointersWithLazyRestoreFragments(transaction: yapRead, block: block)
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

// GRDB TODO: Nice to have: pull all of the YDB finder logic into this file.
struct YAPDBAttachmentFinderAdapter: AttachmentFinderAdapter {

    private let threadUniqueId: String

    init(threadUniqueId: String) {
        self.threadUniqueId = threadUniqueId
    }

    // MARK: - static methods

    static func unfailedAttachmentPointerIds(transaction: YapDatabaseReadTransaction) -> [String] {
        return OWSFailedAttachmentDownloadsJob.unfailedAttachmentPointerIds(with: transaction)
    }

    static func enumerateAttachmentPointersWithLazyRestoreFragments(transaction: YapDatabaseReadTransaction, block: @escaping (TSAttachmentPointer, UnsafeMutablePointer<ObjCBool>) -> Void) {
        guard let view = transaction.safeViewTransaction(TSLazyRestoreAttachmentsDatabaseViewExtensionName) else {
            owsFailDebug("Could not load view transaction.")
            return
        }

        view.safe_enumerateKeysAndObjects(inGroup: TSLazyRestoreAttachmentsGroup,
                                          extensionName: TSLazyRestoreAttachmentsDatabaseViewExtensionName) { (_, _, object, _, stopPtr) in
                                            guard let job = object as? TSAttachmentPointer else {
                                                owsFailDebug("unexpected job: \(type(of: object))")
                                                return
                                            }
                                            block(job, stopPtr)
        }
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

    static func unfailedAttachmentPointerIds(transaction: ReadTransaction) -> [String] {
        let sql: String = """
        SELECT \(attachmentColumn: .uniqueId)
        FROM \(AttachmentRecord.databaseTableName)
        WHERE \(attachmentColumn: .recordType) = \(SDSRecordType.attachmentPointer.rawValue)
        AND \(attachmentColumn: .state) != ?
        """
        var result = [String]()
        do {
            let cursor = try String.fetchCursor(transaction.database,
                                                sql: sql,
                                                arguments: [TSAttachmentPointerState.failed.rawValue])
            while let uniqueId = try cursor.next() {
                result.append(uniqueId)
            }
        } catch {
            owsFailDebug("error: \(error)")
        }
        return result
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
