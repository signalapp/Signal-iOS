import SessionUtilitiesKit

public extension VisibleMessage {

    @objc(SNQuote)
    class Quote : NSObject, NSCoding {
        public var timestamp: UInt64?
        public var publicKey: String?
        public var text: String?
        public var attachmentID: String?

        public var isValid: Bool { timestamp != nil && publicKey != nil }

        public override init() { super.init() }
        
        internal init(timestamp: UInt64, publicKey: String, text: String?, attachmentID: String?) {
            self.timestamp = timestamp
            self.publicKey = publicKey
            self.text = text
            self.attachmentID = attachmentID
        }

        public required init?(coder: NSCoder) {
            if let timestamp = coder.decodeObject(forKey: "timestamp") as! UInt64? { self.timestamp = timestamp }
            if let publicKey = coder.decodeObject(forKey: "authorId") as! String? { self.publicKey = publicKey }
            if let text = coder.decodeObject(forKey: "body") as! String? { self.text = text }
            if let attachmentID = coder.decodeObject(forKey: "attachmentID") as! String? { self.attachmentID = attachmentID }
        }

        public func encode(with coder: NSCoder) {
            coder.encode(timestamp, forKey: "timestamp")
            coder.encode(publicKey, forKey: "authorId")
            coder.encode(text, forKey: "body")
            coder.encode(attachmentID, forKey: "attachmentID")
        }

        public static func fromProto(_ proto: SNProtoDataMessageQuote) -> Quote? {
            let timestamp = proto.id
            let publicKey = proto.author
            let text = proto.text
            return Quote(timestamp: timestamp, publicKey: publicKey, text: text, attachmentID: nil)
        }

        public func toProto() -> SNProtoDataMessageQuote? {
            preconditionFailure("Use toProto(using:) instead.")
        }

        public func toProto(using transaction: YapDatabaseReadWriteTransaction) -> SNProtoDataMessageQuote? {
            guard let timestamp = timestamp, let publicKey = publicKey else {
                SNLog("Couldn't construct quote proto from: \(self).")
                return nil
            }
            let quoteProto = SNProtoDataMessageQuote.builder(id: timestamp, author: publicKey)
            if let text = text { quoteProto.setText(text) }
            addAttachmentsIfNeeded(to: quoteProto, using: transaction)
            do {
                return try quoteProto.build()
            } catch {
                SNLog("Couldn't construct quote proto from: \(self).")
                return nil
            }
        }

        private func addAttachmentsIfNeeded(to quoteProto: SNProtoDataMessageQuote.SNProtoDataMessageQuoteBuilder, using transaction: YapDatabaseReadWriteTransaction) {
            guard let attachmentID = attachmentID else { return }
            guard let stream = TSAttachment.fetch(uniqueId: attachmentID, transaction: transaction) as? TSAttachmentStream, stream.isUploaded else {
                #if DEBUG
                preconditionFailure("Sending a message before all associated attachments have been uploaded.")
                #else
                return
                #endif
            }
            let quotedAttachmentProto = SNProtoDataMessageQuoteQuotedAttachment.builder()
            quotedAttachmentProto.setContentType(stream.contentType)
            if let fileName = stream.sourceFilename { quotedAttachmentProto.setFileName(fileName) }
            guard let attachmentProto = stream.buildProto() else {
                return SNLog("Ignoring invalid attachment for quoted message.")
            }
            quotedAttachmentProto.setThumbnail(attachmentProto)
            do {
                try quoteProto.addAttachments(quotedAttachmentProto.build())
            } catch {
                SNLog("Couldn't construct quoted attachment proto from: \(self).")
            }
        }
        
        // MARK: Description
        public override var description: String {
            """
            Quote(
                timestamp: \(timestamp?.description ?? "null"),
                publicKey: \(publicKey ?? "null"),
                text: \(text ?? "null"),
                attachmentID: \(attachmentID ?? "null")
            )
            """
        }
    }
}
