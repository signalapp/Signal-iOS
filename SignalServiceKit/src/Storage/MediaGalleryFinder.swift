//
//  Copyright (c) 2019 Open Whisper Systems. All rights reserved.
//

import Foundation
import GRDBCipher

protocol MediaGalleryFinder {
    associatedtype ReadTransaction

    func mostRecentMediaAttachment(transaction: ReadTransaction) -> TSAttachment?
    func mediaCount(transaction: ReadTransaction) -> UInt
    func mediaIndex(attachment: TSAttachmentStream, transaction: ReadTransaction) -> Int?
    func enumerateMediaAttachments(range: NSRange, transaction: ReadTransaction, block: @escaping (TSAttachment) -> Void)
}

public class AnyMediaGalleryFinder {
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
}

// MARK: - GRDB

@objc
public class GRDBMediaGalleryFinder: NSObject {

    let thread: TSThread
    init(thread: TSThread) {
        self.thread = thread
    }

    // MARK: - 

    var threadUniqueId: String {
        return thread.uniqueId
    }

    public static func setup(storage: GRDBDatabaseStorageAdapter) {
        storage.add(function: isVisualMediaContentTypeDatabaseFunction)
    }

    public static let isVisualMediaContentTypeDatabaseFunction = DatabaseFunction("IsVisualMediaContentType") { (args: [DatabaseValue]) -> DatabaseValueConvertible? in
        guard let contentType = String.fromDatabaseValue(args[0]) else {
            throw OWSErrorMakeAssertionError("unexpected arguments: \(args)")
        }

        return MIMETypeUtil.isVisualMedia(contentType)
    }
}

extension GRDBMediaGalleryFinder: MediaGalleryFinder {
    typealias ReadTransaction = GRDBReadTransaction

    func mostRecentMediaAttachment(transaction: GRDBReadTransaction) -> TSAttachment? {
        let sql = """
            SELECT \(AttachmentRecord.databaseTableName).*
            FROM \(AttachmentRecord.databaseTableName)
            LEFT JOIN \(InteractionRecord.databaseTableName)
                ON \(attachmentColumn: .albumMessageId) = \(interactionColumnFullyQualified: .uniqueId)
                AND \(interactionColumn: .threadUniqueId) = ?
                AND \(interactionColumn: .isViewOnceMessage) = FALSE
            WHERE \(attachmentColumnFullyQualified: .recordType) = \(SDSRecordType.attachmentStream.rawValue)
                AND \(attachmentColumn: .albumMessageId) IS NOT NULL
                AND IsVisualMediaContentType(\(attachmentColumn: .contentType)) IS TRUE
            ORDER BY
                \(interactionColumnFullyQualified: .id) DESC,
                \(attachmentColumnFullyQualified: .id) DESC
            LIMIT 1
        """

        // GRDB TODO: migrate such that attachment.id reflects ordering in TSInteraction.attachmentIds
        let cursor = TSAttachment.grdbFetchCursor(sql: sql, arguments: [threadUniqueId], transaction: transaction)
        return try! cursor.next()
    }

    func mediaCount(transaction: GRDBReadTransaction) -> UInt {
        let sql = """
        SELECT
            COUNT(*)
        FROM \(AttachmentRecord.databaseTableName)
        LEFT JOIN \(InteractionRecord.databaseTableName)
            ON \(attachmentColumn: .albumMessageId) = \(interactionColumnFullyQualified: .uniqueId)
            AND \(interactionColumn: .threadUniqueId) = ?
            AND \(interactionColumn: .isViewOnceMessage) = FALSE
        WHERE \(attachmentColumnFullyQualified: .recordType) = \(SDSRecordType.attachmentStream.rawValue)
            AND \(attachmentColumn: .albumMessageId) IS NOT NULL
            AND IsVisualMediaContentType(\(attachmentColumn: .contentType)) IS TRUE
        """

        return try! UInt.fetchOne(transaction.database, sql: sql, arguments: [threadUniqueId]) ?? 0
    }

    func enumerateMediaAttachments(range: NSRange, transaction: GRDBReadTransaction, block: @escaping (TSAttachment) -> Void) {
        let sql = """
        SELECT \(AttachmentRecord.databaseTableName).*
        FROM \(AttachmentRecord.databaseTableName)
        LEFT JOIN \(InteractionRecord.databaseTableName)
            ON \(attachmentColumn: .albumMessageId) = \(interactionColumnFullyQualified: .uniqueId)
            AND \(interactionColumn: .threadUniqueId) = ?
            AND \(interactionColumn: .isViewOnceMessage) = FALSE
        WHERE \(attachmentColumnFullyQualified: .recordType) = \(SDSRecordType.attachmentStream.rawValue)
            AND \(attachmentColumn: .albumMessageId) IS NOT NULL
            AND IsVisualMediaContentType(\(attachmentColumn: .contentType)) IS TRUE
        ORDER BY
            \(interactionColumnFullyQualified: .id) DESC,
            \(attachmentColumnFullyQualified: .id) DESC
        """

        // GRDB TODO: migrate such that attachment.id reflects ordering in TSInteraction.attachmentIds
        let cursor = TSAttachment.grdbFetchCursor(sql: sql, arguments: [threadUniqueId], transaction: transaction)
        while let next = try! cursor.next() {
            block(next)
        }
    }

    func mediaIndex(attachment: TSAttachmentStream, transaction: GRDBReadTransaction) -> Int? {
        let sql = """
        SELECT rowNumber
        FROM (
            SELECT
                ROW_NUMBER() OVER (
                    ORDER BY
                        \(interactionColumnFullyQualified: .id) DESC,
                        \(attachmentColumnFullyQualified: .id) DESC
                ) as rowNumber,
                \(attachmentColumnFullyQualified: .uniqueId)
            FROM \(AttachmentRecord.databaseTableName)
            LEFT JOIN \(InteractionRecord.databaseTableName)
                ON \(attachmentColumn: .albumMessageId) = \(interactionColumnFullyQualified: .uniqueId)
                AND \(interactionColumn: .threadUniqueId) = ?
                AND \(interactionColumn: .isViewOnceMessage) = FALSE
            WHERE \(attachmentColumnFullyQualified: .recordType) = \(SDSRecordType.attachmentStream.rawValue)
              AND \(attachmentColumn: .albumMessageId) IS NOT NULL
              AND IsVisualMediaContentType(\(attachmentColumn: .contentType)) IS TRUE
        )
        WHERE \(attachmentColumn: .uniqueId) = ?
        """

        return try! Int.fetchOne(transaction.database, sql: sql, arguments: [threadUniqueId, attachment.uniqueId])
    }
}
