//
//  Copyright (c) 2019 Open Whisper Systems. All rights reserved.
//

import Foundation
import GRDBCipher

protocol AttachmentFinderAdapter {
    associatedtype ReadTransaction

    static func unfailedAttachmentPointerIds(transaction: ReadTransaction) -> [String]
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
}

private func assertionError(_ description: String) -> Error {
    return OWSErrorMakeAssertionError(description)
}
