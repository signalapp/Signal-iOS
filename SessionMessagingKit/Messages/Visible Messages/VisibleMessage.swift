import SessionUtilitiesKit

@objc(SNVisibleMessage)
public final class VisibleMessage : Message {
    @objc public var text: String?
    @objc public var attachmentIDs: [String] = []
    @objc public var quote: Quote?
    @objc public var linkPreview: LinkPreview?
    @objc public var contact: Contact?
    @objc public var profile: Profile?

    // MARK: Initialization
    public override init() { super.init() }

    // MARK: Validation
    public override var isValid: Bool {
        guard super.isValid else { return false }
        if !attachmentIDs.isEmpty { return true }
        if let text = text?.trimmingCharacters(in: .whitespacesAndNewlines), !text.isEmpty { return true }
        return false
    }

    // MARK: Coding
    public required init?(coder: NSCoder) {
        super.init(coder: coder)
        if let text = coder.decodeObject(forKey: "body") as! String? { self.text = text }
        if let attachmentIDs = coder.decodeObject(forKey: "attachments") as! [String]? { self.attachmentIDs = attachmentIDs }
        if let quote = coder.decodeObject(forKey: "quote") as! Quote? { self.quote = quote }
        if let linkPreview = coder.decodeObject(forKey: "linkPreview") as! LinkPreview? { self.linkPreview = linkPreview }
        // TODO: Contact
        if let profile = coder.decodeObject(forKey: "profile") as! Profile? { self.profile = profile }
    }

    public override func encode(with coder: NSCoder) {
        super.encode(with: coder)
        coder.encode(text, forKey: "body")
        coder.encode(attachmentIDs, forKey: "attachments")
        coder.encode(quote, forKey: "quote")
        coder.encode(linkPreview, forKey: "linkPreview")
        // TODO: Contact
        coder.encode(profile, forKey: "profile")
    }

    // MARK: Proto Conversion
    public override class func fromProto(_ proto: SNProtoContent) -> VisibleMessage? {
        guard let dataMessage = proto.dataMessage else { return nil }
        let result = VisibleMessage()
        result.text = dataMessage.body
        // Attachments are handled in MessageReceiver
        if let quoteProto = dataMessage.quote, let quote = Quote.fromProto(quoteProto) { result.quote = quote }
        if let linkPreviewProto = dataMessage.preview.first, let linkPreview = LinkPreview.fromProto(linkPreviewProto) { result.linkPreview = linkPreview }
        // TODO: Contact
        if let profile = Profile.fromProto(dataMessage) { result.profile = profile }
        return result
    }

    public override func toProto() -> SNProtoContent? {
        preconditionFailure("Use toProto(using:) instead.")
    }
    
    public func toProto(using transaction: YapDatabaseReadWriteTransaction) -> SNProtoContent? {
        let proto = SNProtoContent.builder()
        var attachmentIDs = self.attachmentIDs
        let dataMessage: SNProtoDataMessage.SNProtoDataMessageBuilder
        // Profile
        if let profile = profile, let profileProto = profile.toProto() {
            dataMessage = profileProto.asBuilder()
        } else {
            dataMessage = SNProtoDataMessage.builder()
        }
        // Text
        if let text = text { dataMessage.setBody(text) }
        // Quote
        if let quotedAttachmentID = quote?.attachmentID, let index = attachmentIDs.firstIndex(of: quotedAttachmentID) {
            attachmentIDs.remove(at: index)
        }
        if let quote = quote, let quoteProto = quote.toProto(using: transaction) { dataMessage.setQuote(quoteProto) }
        // Link preview
        if let linkPreviewAttachmentID = linkPreview?.attachmentID, let index = attachmentIDs.firstIndex(of: linkPreviewAttachmentID) {
            attachmentIDs.remove(at: index)
        }
        if let linkPreview = linkPreview, let linkPreviewProto = linkPreview.toProto(using: transaction) { dataMessage.setPreview([ linkPreviewProto ]) }
        // Attachments
        let attachments = attachmentIDs.compactMap { TSAttachmentStream.fetch(uniqueId: $0, transaction: transaction) }
        if !attachments.allSatisfy({ $0.isUploaded }) {
            #if DEBUG
            preconditionFailure("Sending a message before all associated attachments have been uploaded.")
            #endif
        }
        let attachmentProtos = attachments.compactMap { $0.buildProto() }
        dataMessage.setAttachments(attachmentProtos)
        // TODO: Contact
        // Build
        do {
            proto.setDataMessage(try dataMessage.build())
            return try proto.build()
        } catch {
            SNLog("Couldn't construct visible message proto from: \(self).")
            return nil
        }
    }
}
