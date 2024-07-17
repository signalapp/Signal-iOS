//
// Copyright 2024 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
import GRDB

extension TSAttachmentMigration {

    enum TSMessageMigration {

        private static func unarchive<T: NSCoding>(_ data: Data) throws -> T {
            let unarchiver = try NSKeyedUnarchiver(forReadingFrom: data)
            unarchiver.requiresSecureCoding = false
            TSAttachmentMigration.prepareNSCodingMappings(unarchiver: unarchiver)
            let decoded = try unarchiver.decodeTopLevelObject(of: [T.self], forKey: NSKeyedArchiveRootObjectKey)
            guard let decoded = decoded as? T else {
                throw OWSAssertionError("Unexpected type when decoding")
            }
            return decoded
        }

        private static func bodyAttachmentIds(messageRow: Row) throws -> [String] {
            guard let encoded = messageRow["attachmentIds"] as? Data else {
                return []
            }
            let decoded: NSArray = try unarchive(encoded)

            var array = [String]()
            try decoded.forEach { element in
                guard let attachmentId = element as? String else {
                    throw OWSAssertionError("Invalid attachment id")
                }
                array.append(attachmentId)
            }
            return array
        }

        private static func contactShare(messageRow: Row) throws -> TSAttachmentMigration.OWSContact? {
            guard let encoded = messageRow["contactShare"] as? Data else {
                return nil
            }
            return try unarchive(encoded)
        }

        private static func contactAttachmentId(messageRow: Row) throws -> String? {
            return try contactShare(messageRow: messageRow)?.avatarAttachmentId
        }

        private static func messageSticker(messageRow: Row) throws -> TSAttachmentMigration.MessageSticker? {
            guard let encoded = messageRow["messageSticker"] as? Data else {
                return nil
            }
            return try unarchive(encoded)
        }

        private static func stickerAttachmentId(messageRow: Row) throws -> String? {
            return try messageSticker(messageRow: messageRow)?.attachmentId
        }

        private static func linkPreview(messageRow: Row) throws -> TSAttachmentMigration.OWSLinkPreview? {
            guard let encoded = messageRow["linkPreview"] as? Data else {
                return nil
            }
            return try unarchive(encoded)
        }

        private static func linkPreviewAttachmentId(messageRow: Row) throws -> String? {
            return try linkPreview(messageRow: messageRow)?.imageAttachmentId
        }

        private static func quotedMessage(messageRow: Row) throws -> TSAttachmentMigration.TSQuotedMessage? {
            guard let encoded = messageRow["quotedMessage"] as? Data else {
                return nil
            }
            return try unarchive(encoded)
        }

        private static func quoteAttachmentId(messageRow: Row) throws -> String? {
            return try quotedMessage(messageRow: messageRow)?.quotedAttachment?.rawAttachmentId.nilIfEmpty
        }

        private static func archive(_ value: Any) throws -> Data {
            let archiver = NSKeyedArchiver(requiringSecureCoding: false)
            TSAttachmentMigration.prepareNSCodingMappings(archiver: archiver)
            archiver.encode(value, forKey: NSKeyedArchiveRootObjectKey)
            return archiver.encodedData
        }

        private static func updateMessageRow(
            rowId: Int64,
            bodyAttachmentIds: [String]?,
            contact: TSAttachmentMigration.OWSContact?,
            messageSticker: TSAttachmentMigration.MessageSticker?,
            linkPreview: TSAttachmentMigration.OWSLinkPreview?,
            quotedMessage: TSAttachmentMigration.TSQuotedMessage?,
            tx: GRDBWriteTransaction
        ) throws {
            var sql = "UPDATE model_TSInteraction SET "
            var arguments = StatementArguments()

            var columns = [String]()
            if let bodyAttachmentIds {
                columns.append("attachmentIds")
                _ = arguments.append(contentsOf: [try archive(bodyAttachmentIds)])
            }
            if let contact {
                columns.append("contactShare")
                _ = arguments.append(contentsOf: [try archive(contact)])
            }
            if let messageSticker {
                columns.append("messageSticker")
                _ = arguments.append(contentsOf: [try archive(messageSticker)])
            }
            if let linkPreview {
                columns.append("linkPreview")
                _ = arguments.append(contentsOf: [try archive(linkPreview)])
            }
            if let quotedMessage {
                columns.append("quotedMessage")
                _ = arguments.append(contentsOf: [try archive(quotedMessage)])
            }

            sql.append(columns.map({ $0 + " = ?"}).joined(separator: ", "))
            sql.append(" WHERE id = ?;")
            _ = arguments.append(contentsOf: [rowId])
            tx.execute(sql: sql, arguments: arguments)
        }
    }
}
