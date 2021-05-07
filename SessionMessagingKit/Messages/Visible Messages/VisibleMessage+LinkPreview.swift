import SessionUtilitiesKit

public extension VisibleMessage {

    @objc(SNLinkPreview)
    class LinkPreview : NSObject, NSCoding {
        public var title: String?
        public var url: String?
        public var attachmentID: String?

        public var isValid: Bool { title != nil && url != nil && attachmentID != nil }

        internal init(title: String?, url: String, attachmentID: String?) {
            self.title = title
            self.url = url
            self.attachmentID = attachmentID
        }

        public required init?(coder: NSCoder) {
            if let title = coder.decodeObject(forKey: "title") as! String? { self.title = title }
            if let url = coder.decodeObject(forKey: "urlString") as! String? { self.url = url }
            if let attachmentID = coder.decodeObject(forKey: "attachmentID") as! String? { self.attachmentID = attachmentID }
        }

        public func encode(with coder: NSCoder) {
            coder.encode(title, forKey: "title")
            coder.encode(url, forKey: "urlString")
            coder.encode(attachmentID, forKey: "attachmentID")
        }

        public static func fromProto(_ proto: SNProtoDataMessagePreview) -> LinkPreview? {
            let title = proto.title
            let url = proto.url
            return LinkPreview(title: title, url: url, attachmentID: nil)
        }

        public func toProto() -> SNProtoDataMessagePreview? {
            preconditionFailure("Use toProto(using:) instead.")
        }

        public func toProto(using transaction: YapDatabaseReadWriteTransaction) -> SNProtoDataMessagePreview? {
            guard let url = url else {
                SNLog("Couldn't construct link preview proto from: \(self).")
                return nil
            }
            let linkPreviewProto = SNProtoDataMessagePreview.builder(url: url)
            if let title = title { linkPreviewProto.setTitle(title) }
            if let attachmentID = attachmentID, let stream = TSAttachment.fetch(uniqueId: attachmentID, transaction: transaction) as? TSAttachmentStream,
                let attachmentProto = stream.buildProto() {
                linkPreviewProto.setImage(attachmentProto)
            }
            do {
                return try linkPreviewProto.build()
            } catch {
                SNLog("Couldn't construct link preview proto from: \(self).")
                return nil
            }
        }
        
        // MARK: Description
        public override var description: String {
            """
            LinkPreview(
                title: \(title ?? "null"),
                url: \(url ?? "null"),
                attachmentID: \(attachmentID ?? "null")
            )
            """
        }
    }
}
