
@objc(SNVisibleMessage)
public final class VisibleMessage : Message {
    public var text: String?
    public var attachmentIDs: [String] = []
    public var quote: Quote?
    public var linkPreview: LinkPreview?
    public var contact: Contact?

}
