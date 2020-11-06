import SessionUtilities

@objc(SNVisibleMessage)
public final class VisibleMessage : Message {
    public var text: String?
    public var attachmentIDs: [String] = []
    public var quote: Quote?
    public var linkPreview: LinkPreview?
    public var contact: Contact?
    public var profile: Profile?

    // MARK: Initialization
    public override init() { super.init() }

    // MARK: Coding
    public required init?(coder: NSCoder) {
        super.init(coder: coder)
        if let text = coder.decodeObject(forKey: "text") as! String? { self.text = text }
        if let attachmentIDs = coder.decodeObject(forKey: "attachmentIDs") as! [String]? { self.attachmentIDs = attachmentIDs }
    }

    public override func encode(with coder: NSCoder) {
        super.encode(with: coder)
        coder.encode(text, forKey: "text")
        coder.encode(attachmentIDs, forKey: "attachmentIDs")
    }

    // MARK: Proto Conversion
    public override class func fromProto(_ proto: SNProtoContent) -> VisibleMessage? {
        guard let dataMessage = proto.dataMessage else { return nil }
        let result = VisibleMessage()
        result.text = dataMessage.body
        result.attachmentIDs = [] // TODO: Attachments
        if let quoteProto = dataMessage.quote, let quote = Quote.fromProto(quoteProto) { result.quote = quote }
        if let linkPreviewProto = dataMessage.preview.first, let linkPreview = LinkPreview.fromProto(linkPreviewProto) { result.linkPreview = linkPreview }
        // TODO: Contact
        if let profile = Profile.fromProto(dataMessage) { result.profile = profile }
        return result
    }

    public override func toProto() -> SNProtoContent? {
        let proto = SNProtoContent.builder()
        let dataMessage: SNProtoDataMessage.SNProtoDataMessageBuilder
        if let profile = profile, let profileProto = profile.toProto() {
            dataMessage = profileProto.asBuilder()
        } else {
            dataMessage = SNProtoDataMessage.builder()
        }
        if let text = text { dataMessage.setBody(text) }
        // TODO: Attachments
        if let quote = quote, let quoteProto = quote.toProto() { dataMessage.setQuote(quoteProto) }
        if let linkPreview = linkPreview, let linkPreviewProto = linkPreview.toProto() { dataMessage.setPreview([ linkPreviewProto ]) }
        // TODO: Contact
        do {
            proto.setDataMessage(try dataMessage.build())
            return try proto.build()
        } catch {
            SNLog("Couldn't construct visible message proto from: \(self).")
            return nil
        }
    }
}
