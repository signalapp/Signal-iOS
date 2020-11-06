import SessionUtilities

public extension VisibleMessage {

    @objc(SNLinkPreview)
    class LinkPreview : NSObject, NSCoding {
        public var title: String?
        public var url: String?

        internal init(title: String?, url: String) {
            self.title = title
            self.url = url
        }

        public required init?(coder: NSCoder) {
            if let title = coder.decodeObject(forKey: "title") as! String? { self.title = title }
            if let url = coder.decodeObject(forKey: "url") as! String? { self.url = url }
        }

        public func encode(with coder: NSCoder) {
            coder.encode(title, forKey: "title")
            coder.encode(url, forKey: "url")
        }

        public static func fromProto(_ proto: SNProtoDataMessagePreview) -> LinkPreview? {
            let title = proto.title
            let url = proto.url
            return LinkPreview(title: title, url: url)
        }

        public func toProto() -> SNProtoDataMessagePreview? {
            guard let url = url else {
                SNLog("Couldn't construct link preview proto from: \(self).")
                return nil
            }
            let linkPreviewProto = SNProtoDataMessagePreview.builder(url: url)
            if let title = title { linkPreviewProto.setTitle(title) }
            do {
                return try linkPreviewProto.build()
            } catch {
                SNLog("Couldn't construct link preview proto from: \(self).")
                return nil
            }
        }
    }
}
