import CoreGraphics
import SessionUtilitiesKit

public extension VisibleMessage {

    @objc(SNAttachment)
    class Attachment : NSObject, NSCoding {
        public var fileName: String?
        public var contentType: String?
        public var key: Data?
        public var digest: Data?
        public var kind: Kind?
        public var caption: String?
        public var size: CGSize?
        public var sizeInBytes: UInt?
        public var url: String?

        public var isValid: Bool {
            // key and digest can be nil for open group attachments
            contentType != nil && kind != nil && size != nil && sizeInBytes != nil && url != nil
        }

        public enum Kind : String {
            case voiceMessage, generic
        }

        public override init() { super.init() }

        public required init?(coder: NSCoder) {
            if let fileName = coder.decodeObject(forKey: "fileName") as! String? { self.fileName = fileName }
            if let contentType = coder.decodeObject(forKey: "contentType") as! String? { self.contentType = contentType }
            if let key = coder.decodeObject(forKey: "key") as! Data? { self.key = key }
            if let digest = coder.decodeObject(forKey: "digest") as! Data? { self.digest = digest }
            if let rawKind = coder.decodeObject(forKey: "kind") as! String? { self.kind = Kind(rawValue: rawKind) }
            if let caption = coder.decodeObject(forKey: "caption") as! String? { self.caption = caption }
            if let size = coder.decodeObject(forKey: "size") as! CGSize? { self.size = size }
            if let sizeInBytes = coder.decodeObject(forKey: "sizeInBytes") as! UInt? { self.sizeInBytes = sizeInBytes }
            if let url = coder.decodeObject(forKey: "url") as! String? { self.url = url }
        }

        public func encode(with coder: NSCoder) {
            coder.encode(fileName, forKey: "fileName")
            coder.encode(contentType, forKey: "contentType")
            coder.encode(key, forKey: "key")
            coder.encode(digest, forKey: "digest")
            coder.encode(kind?.rawValue, forKey: "kind")
            coder.encode(caption, forKey: "caption")
            coder.encode(size, forKey: "size")
            coder.encode(sizeInBytes, forKey: "sizeInBytes")
            coder.encode(url, forKey: "url")
        }

        public static func fromProto(_ proto: SNProtoAttachmentPointer) -> Attachment? {
            let result = Attachment()
            result.fileName = proto.fileName
            func inferContentType() -> String {
                guard let fileName = result.fileName, let fileExtension = URL(string: fileName)?.pathExtension else { return OWSMimeTypeApplicationOctetStream }
                return MIMETypeUtil.mimeType(forFileExtension: fileExtension) ?? OWSMimeTypeApplicationOctetStream
            }
            result.contentType = proto.contentType ?? inferContentType()
            result.key = proto.key
            result.digest = proto.digest
            let kind: VisibleMessage.Attachment.Kind
            if proto.hasFlags && (proto.flags & UInt32(SNProtoAttachmentPointer.SNProtoAttachmentPointerFlags.voiceMessage.rawValue)) > 0 {
                kind = .voiceMessage
            } else {
                kind = .generic
            }
            result.kind = kind
            result.caption = proto.hasCaption ? proto.caption : nil
            let size: CGSize
            if proto.hasWidth && proto.width > 0 && proto.hasHeight && proto.height > 0 {
                size = CGSize(width: Int(proto.width), height: Int(proto.height))
            } else {
                size = CGSize.zero
            }
            result.size = size
            result.sizeInBytes = proto.size > 0 ? UInt(proto.size) : nil
            result.url = proto.url
            return result
        }

        public func toProto() -> SNProtoDataMessageQuote? {
            fatalError("Not implemented.")
        }
    }
}
