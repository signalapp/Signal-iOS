//
//  Copyright (c) 2019 Open Whisper Systems. All rights reserved.
//

import Foundation
import GRDBCipher

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
}

private func assertionError(_ description: String) -> Error {
    return OWSErrorMakeAssertionError(description)
}
