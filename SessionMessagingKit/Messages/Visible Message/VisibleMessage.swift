
@objc(SNVisibleMessage)
public final class VisibleMessage : Message {
    public var text: String?
    public var attachmentIDs: [String] = []
    public var quote: Quote?
    public var linkPreview: LinkPreview?
    public var contact: Contact?
    public var profile: Profile?

    public override class func fromProto(_ proto: SNProtoContent) -> VisibleMessage? {
        return nil
//        guard let data = proto.dataMessage,
//            let text = data.body else { return nil }
//        let result = VisibleMessage()
//        result.text = text
//        return result
    }
}
