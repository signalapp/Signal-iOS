// Copyright © 2022 Rangeproof Pty Ltd. All rights reserved.

import Foundation
import GRDB
import SessionUtilitiesKit

public extension VisibleMessage {

    struct VMQuote: Codable {
        public let timestamp: UInt64?
        public let publicKey: String?
        public let text: String?
        public let attachmentId: String?

        public var isValid: Bool { timestamp != nil && publicKey != nil }
        
        // MARK: - Initialization

        internal init(timestamp: UInt64, publicKey: String, text: String?, attachmentId: String?) {
            self.timestamp = timestamp
            self.publicKey = publicKey
            self.text = text
            self.attachmentId = attachmentId
        }
        
        // MARK: - Proto Conversion

        public static func fromProto(_ proto: SNProtoDataMessageQuote) -> VMQuote? {
            return VMQuote(
                timestamp: proto.id,
                publicKey: proto.author,
                text: proto.text,
                attachmentId: nil
            )
        }

        public func toProto() -> SNProtoDataMessageQuote? {
            preconditionFailure("Use toProto(_:) instead.")
        }

        public func toProto(_ db: Database) -> SNProtoDataMessageQuote? {
            guard let timestamp = timestamp, let publicKey = publicKey else {
                SNLog("Couldn't construct quote proto from: \(self).")
                return nil
            }
            let quoteProto = SNProtoDataMessageQuote.builder(id: timestamp, author: publicKey)
            if let text = text { quoteProto.setText(text) }
            addAttachmentsIfNeeded(db, to: quoteProto)
            do {
                return try quoteProto.build()
            } catch {
                SNLog("Couldn't construct quote proto from: \(self).")
                return nil
            }
        }

        private func addAttachmentsIfNeeded(_ db: Database, to quoteProto: SNProtoDataMessageQuote.SNProtoDataMessageQuoteBuilder) {
            guard let attachmentId = attachmentId else { return }
            guard
                let attachment: Attachment = try? Attachment.fetchOne(db, id: attachmentId),
                attachment.state == .uploaded
            else {
                #if DEBUG
                preconditionFailure("Sending a message before all associated attachments have been uploaded.")
                #else
                return
                #endif
            }
            let quotedAttachmentProto = SNProtoDataMessageQuoteQuotedAttachment.builder()
            quotedAttachmentProto.setContentType(attachment.contentType)
            if let fileName = attachment.sourceFilename { quotedAttachmentProto.setFileName(fileName) }
            guard let attachmentProto = attachment.buildProto() else {
                return SNLog("Ignoring invalid attachment for quoted message.")
            }
            quotedAttachmentProto.setThumbnail(attachmentProto)
            do {
                try quoteProto.addAttachments(quotedAttachmentProto.build())
            } catch {
                SNLog("Couldn't construct quoted attachment proto from: \(self).")
            }
        }
        
        // MARK: - Description
        
        public var description: String {
            """
            Quote(
                timestamp: \(timestamp?.description ?? "null"),
                publicKey: \(publicKey ?? "null"),
                text: \(text ?? "null"),
                attachmentId: \(attachmentId ?? "null")
            )
            """
        }
    }
}

// MARK: - Database Type Conversion

public extension VisibleMessage.VMQuote {
    static func from(_ db: Database, quote: Quote) -> VisibleMessage.VMQuote {
        return VisibleMessage.VMQuote(
            timestamp: UInt64(quote.timestampMs),
            publicKey: quote.authorId,
            text: quote.body,
            attachmentId: quote.attachmentId
        )
    }
}
